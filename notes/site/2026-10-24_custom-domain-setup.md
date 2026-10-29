# Custom domain setup — iowatransparencyproject.org

**Status (2026-10-28):** live. Domain bought on Cloudflare; A/AAAA/`www` records added as DNS only; GitHub's DNS check passed and its Let's Encrypt certificate covers the apex and `www`; GitHub committed `docs/CNAME` (`66ff63ce`). Part 3 is done locally (`site/CNAME`, `resources: [CNAME]`, `site-url`; no hardcoded `github.io` paths found) but not committed. Still open: tick **Enforce HTTPS**, account-level TXT verification (2a, optional), Part 4, and the "Afterward" list.

In a scratch project on Quarto 1.10.18, a full render kept an existing `docs/CNAME` even without the `resources` entry, so the risk in Part 3 was smaller than stated; the entry still guarantees the file whenever `docs/` is rebuilt from scratch.

**Plan:** buy the domain from **Cloudflare Registrar**, keep hosting on **GitHub Pages** for now, and point the domain at it. A move to Cloudflare Pages can come later as part of the page-weight work in [`notes/legislature/2026-10-24_multi-session-plan.md`](../legislature/2026-10-24_multi-session-plan.md). Since the domain's DNS will already be on Cloudflare, that move would only mean changing DNS records.

**Cost:** about $10–11/yr for `.org`, plus about $10–11/yr more if you also take the `.com`. Cloudflare sells at cost, so renewals cost the same as the first year. WHOIS privacy and HTTPS are free.

**Current site URL:** `https://mavoss16.github.io/ia_transparency_project/` (Pages serves `docs/` on `main`).

---

## Part 1 — Buy the domain (about 15 min, done by you)

1. **Create a Cloudflare account** at dash.cloudflare.com/sign-up (the free plan).
   - Turn on two-factor authentication right away (*My Profile → Authentication*). Whoever controls this account controls the site's address.
2. **Add a payment method** under *Manage Account → Billing*.
3. **Register the domain:** *Domain Registration → Register Domains* → search `iowatransparencyproject`.
   - Add `iowatransparencyproject.org` to the cart.
   - Optional: also add `iowatransparencyproject.com` to redirect to the `.org` (see Part 4).
   - Confirm the price shown is about $10–11 and isn't marked as a premium name.
4. **Fill in the registrant contact.** ICANN requires real details. Cloudflare hides them from public WHOIS by default, so your name and address are not published.
5. **Leave auto-renew on.** An expired domain can be bought by someone else, and that is the main way projects lose their address.
6. **Check out.** Cloudflare sets up DNS for the domain automatically, so there are no nameservers to change.

## Part 2 — Point the domain at GitHub Pages (about 15 min, done by you)

### 2a. Verify the domain with GitHub (do this first)

This protects against a known takeover problem: if the Pages site is ever turned off while DNS still points at GitHub, someone else could claim the domain on their own Pages site.

1. GitHub → your profile → *Settings → Pages → Add a domain* → enter `iowatransparencyproject.org`.
2. GitHub shows a `TXT` record. In Cloudflare, go to *your domain → DNS → Records → Add record* and paste it in.
3. Back in GitHub, click *Verify*.

### 2b. Add the DNS records in Cloudflare

*Your domain → DNS → Records.* Set **Proxy status = DNS only (grey cloud)** on every record below. If the orange cloud is on, GitHub can't issue the HTTPS certificate.

| Type | Name | Content |
|---|---|---|
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |
| AAAA | `@` | `2606:50c0:8000::153` |
| AAAA | `@` | `2606:50c0:8001::153` |
| AAAA | `@` | `2606:50c0:8002::153` |
| AAAA | `@` | `2606:50c0:8003::153` |
| CNAME | `www` | `mavoss16.github.io` |

Check these IPs against GitHub's docs ("Managing a custom domain for your GitHub Pages site") when you do this; they rarely change.

### 2c. Tell the repo about the domain

1. Make the repo changes in Part 3 first and let them deploy, so the `CNAME` file survives the next CI render.
2. In the repo, go to *Settings → Pages → Custom domain*, enter `iowatransparencyproject.org` and save. A DNS check runs, which can take a few minutes up to a few hours.
3. When **Enforce HTTPS** becomes clickable (the certificate usually takes under an hour), tick it.

After that, `mavoss16.github.io/ia_transparency_project/…` links redirect to the new domain automatically.

## Part 3 — Repo changes (small, can be done by Claude)

The daily CI renders the site and pushes `docs/`. If a `CNAME` file exists only in `docs/`, a full Quarto render can delete it, and the custom domain would silently drop off. To keep it:

1. Create `site/CNAME` containing the single line `iowatransparencyproject.org`.
2. Add it to `_quarto.yml` so Quarto copies it into `docs/` on every render:
   ```yaml
   project:
     resources:
       - CNAME
   ```
3. Set the canonical URL, which is used for the sitemap, canonical links and social previews:
   ```yaml
   website:
     site-url: https://iowatransparencyproject.org
   ```
4. Look for hardcoded `github.io` or `/ia_transparency_project/` paths in the `.qmd` files, `custom.scss` and `R/`. The site moves from a subpath to the domain root, so absolute paths that include the repo name would break. Relative links are fine.

## Part 4 — Optional: redirect the `.com`

If you bought `iowatransparencyproject.com`:

1. In its DNS, add a placeholder record: `A`, name `@`, content `192.0.2.1`, **proxied (orange cloud)**. Do the same for `www`.
2. *Rules → Redirect Rules → Create rule* → match all incoming requests → dynamic redirect to `concat("https://iowatransparencyproject.org", http.request.uri.path)`, status 301, preserve query string.

## Afterward

- Update the repo's *About* box on GitHub with the new URL.
- Update `CLAUDE.md` and the CI/site memory notes to show the new domain.
- Put a reminder in your calendar a few weeks before the renewal date to check that the card on file hasn't expired.
