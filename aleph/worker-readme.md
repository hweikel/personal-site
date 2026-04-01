# Aleph Worker — Setup

## 1. Create the KV namespace

In the Cloudflare dashboard, go to **Workers & Pages → KV** and create a new namespace.
Name it something like `aleph-suggestions`. Copy the namespace ID.

## 2. Update wrangler.toml

- Set `account_id` to your Cloudflare account ID (found in the dashboard sidebar).
- Set `id` under `[[kv_namespaces]]` to the namespace ID from step 1.

## 3. Choose a token

Pick any secret string to use as your shared token (e.g. a random hex string).
Set it as `VALID_TOKEN` at the top of `worker.js`.

## 4. Deploy

```
npx wrangler deploy
```

The deployed Worker URL will be printed on success (e.g. `https://aleph-worker.your-subdomain.workers.dev`).

## 5. Update index.html

In `index.html`, replace the two placeholders near the top of the script:

- `SUGGEST_ENDPOINT` → the deployed Worker URL + `/api/suggest`
  e.g. `"https://aleph-worker.your-subdomain.workers.dev/api/suggest"`
- `SUGGEST_TOKEN` → the same token string you set in `worker.js`

## 6. (Optional) Restrict CORS

Once your site is deployed, replace `"*"` in the worker's `CORS_HEADERS` with your
actual domain (e.g. `"https://yourdomain.com"`) and redeploy.
