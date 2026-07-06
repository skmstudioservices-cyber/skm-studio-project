# SKM Maps Ecosystem

Visual local business directory for Indian MSMEs built on DigiPIN. Zero-language UI (colors, icons, numbers). DPDP-compliant, IDOR-proof.

## Architecture

```
GitLab (private master) -> GitHub mirror -> Cloudflare Pages
                                               |
                                    Supabase (Mumbai ap-south-1)
```

## Cloudflare Pages Projects

| Project | Purpose |
|---|---|
| maps.pages.dev | Public directory + SEO |
| dash.pages.dev | Super admin (protect with CF Zero Trust) |
| admins.pages.dev | Regional managers |
| profiles.pages.dev | Merchant self-serve dashboard |
| business.pages.dev | Business listings |

## Setup Steps

1. Run `supabase/schema.sql` in Supabase SQL Editor (Mumbai project).
2. Set your Supabase anon key in `apps/maps/public/config.js`.
3. In GitLab CI/CD variables, add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` (masked).
4. Configure GitLab -> GitHub push mirror (Settings > Repository > Mirroring).
5. Protect `dash.pages.dev` with Cloudflare Zero Trust (email OTP, your email only).

## Security Notes

- All data access enforced by Supabase Row Level Security (RLS).
- The anon key is safe to expose publicly; RLS is the security boundary.
- NEVER commit the service_role key anywhere.
