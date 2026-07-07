// Cloudflare Pages Function: POST /api/indexnow  { "urls": ["https://..."] }
// Server-side IndexNow ping (browsers are CORS-blocked from calling IndexNow directly).
// Set INDEXNOW_KEY as an environment variable in the CF Pages project settings,
// and host the key file at /<INDEXNOW_KEY>.txt containing the key itself.

export async function onRequestPost(context) {
  const key = context.env.INDEXNOW_KEY;
  if (!key) return new Response('INDEXNOW_KEY not configured', { status: 500 });

  let body;
  try { body = await context.request.json(); } catch { return new Response('Bad JSON', { status: 400 }); }
  const urls = (body.urls || []).filter(u => typeof u === 'string' && u.startsWith('https://')).slice(0, 100);
  if (!urls.length) return new Response('No valid urls', { status: 400 });

  const host = new URL(urls[0]).host;
  const res = await fetch('https://api.indexnow.org/indexnow', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ host, key, keyLocation: `https://${host}/${key}.txt`, urlList: urls })
  });

  return new Response(JSON.stringify({ status: res.status }), {
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
  });
}
