-- ============================================================
-- SKM Maps Ecosystem - Core Schema (run in Supabase SQL Editor)
-- Region: Mumbai (ap-south-1) for DPDP compliance
-- ============================================================

-- Extensions
create extension if not exists postgis;

-- ------------------------------------------------------------
-- Roles
-- ------------------------------------------------------------
do $$ begin
  create type user_role as enum ('super_admin', 'manager', 'merchant', 'public_viewer');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- User profiles
-- ------------------------------------------------------------
create table if not exists user_profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  phone_mask text,
  assigned_role user_role not null default 'merchant',
  assigned_region text[], -- array of pincodes a manager controls
  updated_at timestamptz default now()
);

-- SECURITY DEFINER helper to avoid recursive RLS lookups
create or replace function get_my_role()
returns user_role
language sql stable security definer set search_path = public as $$
  select assigned_role from user_profiles where id = auth.uid();
$$;

create or replace function get_my_regions()
returns text[]
language sql stable security definer set search_path = public as $$
  select assigned_region from user_profiles where id = auth.uid();
$$;

alter table user_profiles enable row level security;

create policy "own profile read" on user_profiles
  for select to authenticated
  using (id = auth.uid());

create policy "super admin full access" on user_profiles
  for all to authenticated
  using (get_my_role() = 'super_admin')
  with check (get_my_role() = 'super_admin');

-- ------------------------------------------------------------
-- Business listings
-- ------------------------------------------------------------
create table if not exists business_listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  category text not null,
  digipin text unique,
  pincode text not null,
  location geography(point, 4326),
  whatsapp_number text,
  vanity_slug text unique,
  is_premium boolean not null default false,
  is_verified boolean not null default false,
  lang_data jsonb default '{}'::jsonb, -- regional language name/desc overrides
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_listings_pincode on business_listings (pincode);
create index if not exists idx_listings_digipin on business_listings (digipin);
create index if not exists idx_listings_location on business_listings using gist (location);

alter table business_listings enable row level security;

-- Public can read listings (it is a public directory)
create policy "public read listings" on business_listings
  for select to anon, authenticated
  using (true);

-- Merchants can only modify their own listing (IDOR protection)
create policy "merchant own listing write" on business_listings
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "merchant own listing insert" on business_listings
  for insert to authenticated
  with check (owner_id = auth.uid());

-- Managers can update listings only in their assigned pincodes
create policy "manager regional write" on business_listings
  for update to authenticated
  using (get_my_role() = 'manager' and pincode = any(get_my_regions()))
  with check (get_my_role() = 'manager' and pincode = any(get_my_regions()));

-- Super admin full control
create policy "super admin listings" on business_listings
  for all to authenticated
  using (get_my_role() = 'super_admin')
  with check (get_my_role() = 'super_admin');

-- ------------------------------------------------------------
-- Lead tracking (click analytics / outreach proof)
-- ------------------------------------------------------------
create table if not exists lead_tracking (
  id bigserial primary key,
  shop_id uuid not null references business_listings(id) on delete cascade,
  action_type text not null check (action_type in ('whatsapp_click','map_view','seo_view','parcel_booking','vanity_click')),
  user_pincode text,
  device_fingerprint text,
  clicked_at timestamptz default now()
);

create index if not exists idx_leads_shop on lead_tracking (shop_id, clicked_at desc);

alter table lead_tracking enable row level security;

-- Anyone can write a tracking event (insert only, no reads)
create policy "public insert tracking" on lead_tracking
  for insert to anon, authenticated
  with check (true);

-- SECURITY FIX vs original PRD: reads restricted to the shop owner,
-- regional managers, and super admin. NOT all authenticated users.
create policy "owner reads own analytics" on lead_tracking
  for select to authenticated
  using (
    exists (
      select 1 from business_listings b
      where b.id = lead_tracking.shop_id and b.owner_id = auth.uid()
    )
  );

create policy "manager reads regional analytics" on lead_tracking
  for select to authenticated
  using (
    get_my_role() = 'manager' and exists (
      select 1 from business_listings b
      where b.id = lead_tracking.shop_id and b.pincode = any(get_my_regions())
    )
  );

create policy "super admin reads all analytics" on lead_tracking
  for select to authenticated
  using (get_my_role() = 'super_admin');

-- ------------------------------------------------------------
-- Nearby transport/infrastructure reference data (PostGIS)
-- ------------------------------------------------------------
create table if not exists transport_hubs (
  id bigserial primary key,
  name text not null,
  hub_type text not null check (hub_type in ('rail','highway','bus','airport','transport_agency')),
  location geography(point, 4326) not null
);

create index if not exists idx_hubs_location on transport_hubs using gist (location);

alter table transport_hubs enable row level security;
create policy "public read hubs" on transport_hubs
  for select to anon, authenticated using (true);

-- RPC: nearest hubs to a listing (called from the public site)
create or replace function nearest_hubs(lat double precision, lng double precision, max_results int default 5)
returns table (name text, hub_type text, distance_km numeric)
language sql stable security definer set search_path = public as $$
  select h.name, h.hub_type,
         round((st_distance(h.location, st_setsrid(st_makepoint(lng, lat), 4326)::geography) / 1000)::numeric, 1)
  from transport_hubs h
  order by h.location <-> st_setsrid(st_makepoint(lng, lat), 4326)::geography
  limit max_results;
$$;
