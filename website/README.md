# Písmenka — Website

Marketing + support site for [pismenka.com](https://pismenka.com).

## Stack

- **Astro 6** — static site generator. Zero JS shipped on these pages by design.
- **Tailwind CSS 4** — wired through PostCSS (`@tailwindcss/postcss`).
- **Cloudflare Pages** — hosting. Custom domain attached via the Cloudflare API.
- **Wrangler** — CLI used for the actual `pages deploy`.

## Pages

| Path | Source |
|---|---|
| `/` | `src/pages/index.astro` |
| `/support/` | `src/pages/support/index.astro` |
| `/privacy/` | `src/pages/privacy/index.astro` |
| 404 | `src/pages/404.astro` |

`src/layouts/Layout.astro` is the shared shell (header, footer, favicons, OG tags). `src/styles/global.css` is the only CSS file — Tailwind v4 with a small set of custom design tokens (`--color-ink`, `--color-sun`, etc.).

## Local development

From the **repo root**:

```sh
npm install --prefix website
npm run dev --prefix website
```

The dev server starts on `http://localhost:4321/`.

## Production build

```sh
npm run build --prefix website
```

Outputs to `website/dist/`. Astro is configured for static output (no SSR), so any static host works. The `dist/` folder is what Cloudflare Pages serves.

## Deploy

You'll need Wrangler authenticated once:

```sh
npx --prefix website wrangler login
```

Then from the repo root:

```sh
npm run build --prefix website
npm run deploy --prefix website
```

`npm run deploy` runs:

```
wrangler pages deploy dist --project-name pismenka --branch main --commit-dirty=true
```

The `pismenka` project on Cloudflare is already configured to serve from this `dist/` upload.

## Custom Domain Setup

What is already wired:

- The Cloudflare Pages project `pismenka` exists.
- `pismenka.com` and `www.pismenka.com` are attached as custom domains.
- The `pismenka.com` zone is on Cloudflare with the right nameservers.
- DNS records: `pismenka.com` and `www.pismenka.com` both `CNAME → pismenka.pages.dev` (proxied).

Wrangler's OAuth token can deploy Pages and attach custom domains, but Cloudflare does **not** grant `dns_records:write` via OAuth. You need a scoped API token for the DNS step.

### One-time: create the API token

1. Open <https://dash.cloudflare.com/profile/api-tokens>
2. Click **Create Token** → use the **Edit zone DNS** template.
3. Under **Zone Resources**, select **Specific zone** → `pismenka.com`.
4. Click **Continue to summary** → **Create Token**.
5. Copy the token.

### Run the connector

```sh
export CLOUDFLARE_API_TOKEN="paste-token-here"
python3 website/scripts/connect-domain.py
```

The script (`website/scripts/connect-domain.py`) is idempotent. It:

1. Verifies the token can read the `pismenka.com` zone.
2. Re-attaches `pismenka.com` and `www.pismenka.com` to the Pages project if needed.
3. Creates or updates two proxied CNAME records pointing at `pismenka.pages.dev` (and removes conflicting `A`/`AAAA` records on those names).
4. Polls the Pages domain status until both go `active` (Cloudflare issues the TLS cert during this window — usually under a minute).
5. Issues HTTPS HEAD requests against `pismenka.com` and `www.pismenka.com`.

If the script is interrupted or the cert is still issuing, just re-run it.

## Favicons

Generated via Pillow with the system rounded font (`/System/Library/Fonts/SFCompactRounded.ttf` at weight 900). The SVG favicon embeds the actual glyph path extracted with `fontTools` so it renders identically on any device. See `website/scripts/generate-favicons.py` (regenerate any time):

| File | Use |
|---|---|
| `public/favicon.ico` | Multi-res 16/32/48 — older browsers, OS bookmarks |
| `public/favicon.svg` | Modern browser tabs, infinite resolution |
| `public/favicon-16.png`, `-32.png` | Tab fallback |
| `public/apple-touch-icon.png` | 180×180 — iOS home screen |
| `public/icon-192.png`, `icon-512.png` | PWA install (Android / Chrome) + OG image |

## Performance

Pages weigh roughly 7 KB of HTML each. No JavaScript is shipped on the marketing pages, no third-party scripts, no analytics. Cloudflare Pages serves them from the global edge with the cache headers in `public/_headers`.
