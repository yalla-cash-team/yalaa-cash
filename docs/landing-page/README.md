# Yalla Cash — landing page

Maintenance notes for the static site in `landing-page/`. This file and `tools/` live in `docs/landing-page/` on purpose, so the publish folder (`landing-page/`) contains only public website files.

Static, dependency-free Arabic RTL landing page (HTML + CSS + a small progressive-enhancement script). No build step, no third-party requests.

## Preview locally

```powershell
.\docs\landing-page\tools\serve.ps1  # http://localhost:8080  (127.0.0.1 only, serves landing-page/)
# or: python -m http.server 8080 --bind 127.0.0.1 --directory landing-page
```

## Contents

Paths are relative to `landing-page/` unless they start with `docs/`.

| Path | What |
|---|---|
| `index.html` | the page; all download/contact links live here |
| `assets/css/styles.css` | brand tokens (from the Customer app), layout, motion |
| `assets/js/main.js` | reveal-on-scroll + floating mobile download button |
| `assets/fonts/` | Almarai Regular/Bold/ExtraBold, WOFF2 subsets (Arabic + Latin), SIL OFL 1.1 |
| `assets/img/` | logo, favicons, OG card, and the two app screenshots (WebP, 1x/2x) |
| `downloads/yalla-cash.apk` | local-only copy of the v1.1.0 release build, **not referenced by the page** and git-ignored (`*.apk`). Safe to delete; the live download is the GitHub Release below |
| `privacy/index.html` | privacy policy, copied unchanged from `docs/privacy-policy/index.html` |
| `docs/landing-page/tools/` | screenshot harness (`landing_shots_test.dart`) and the preview script; kept out of the publish folder |

## Links (all real, none invented)

- **APK:** `https://github.com/yalla-cash-team/yalaa-cash/releases/latest/download/yalla-cash.apk`, the permanent link to the asset of the newest GitHub Release (currently [`customer-v1.1.0`](https://github.com/yalla-cash-team/yalaa-cash/releases/tag/customer-v1.1.0), tag commit `9af95ee`, 56,826,390 bytes, SHA-256 `6562064d274879d28495a8e3f2bb1fb1db0792852023cf7c0264d9ed006e0e0e`). It redirects to GitHub's release-asset host and is served as an attachment (`application/vnd.android.package-archive`). Used by all four download buttons (header link, hero, closing section, floating mobile button). The asset must always be named `yalla-cash.apk`.
- **Google Play:** `https://play.google.com/store/apps/details?id=com.yallacash.app`. This is the app's own hard-coded listing URL (`customer_shell.dart`). It returned HTTP 200 with the title "Yalla Cash - Apps on Google Play" when checked, while a nonexistent package id returned 404.
- **Contact:** `https://wa.me/963998111295`, the number behind the app's own "contact us" action.
- **Privacy:** `privacy/` (bundled copy of the existing policy).

## Motion

- **Hero entrance** (CSS keyframes): the logo fades in, then the headline lines rise in, then the description, then the two buttons (staggered). Finally the two phones enter from opposite sides.
- **Phones:** each phone has three nested layers, so effects never conflict:
  - `.phone` runs the entrance.
  - `.phone-float` runs an independent float with a slight 3D tilt (7.6 s and 9.2 s cycles, opposite directions).
  - `.phone-tilt` handles the desktop-only mouse parallax (`--mx`/`--my` set by `main.js`).
- **Light effects:** a soft blue glow breathes behind the phones. Every 10 s a light travels around each phone frame (frame edge only, never over the screen).
- **Rest of the page:** sections and step cards reveal on scroll, cards lift on hover, and buttons have hover lift, a hover light pass and press feedback.
- **Performance:** loops pause while the hero is off screen. Only `transform`/`opacity` animate, plus one registered angle for the frame light.
- `prefers-reduced-motion: reduce` turns off all non-essential motion, including the entrance, float, glow, frame light, parallax and hover lifts.

## Regenerating the screenshots

The two phone screenshots come from the real Customer app UI (`CustomerShell`, real theme and Almarai family), rendered by a Flutter test harness at 360×800 @3x. Only the **data** is seeded: the app's built-in demo stores (`YallaCashStore.demo()`), a demo customer, and five sample loyalty transactions. The banner is a plain brand-gradient image with the real logo mark.

```powershell
Copy-Item docs\landing-page\tools\landing_shots_test.dart apps\yalla_cash_customer\test\_tmp_landing_shots_test.dart
cd apps\yalla_cash_customer
flutter test test/_tmp_landing_shots_test.dart --dart-define=OUT=<absolute output dir>
Remove-Item test\_tmp_landing_shots_test.dart      # the _tmp_ prefix is git-ignored
```

Then resize to 540 px and 1080 px wide and save as WebP (`home.webp`, `home@2x.webp`, `wallet.webp`, `wallet@2x.webp`).

## Deploying to Render (static site)

Create it manually in the Render dashboard (no `render.yaml` is needed):

| Setting | Value |
|---|---|
| Service type | Static Site |
| Name | `yalla-cash-landing` |
| Repository | `yalla-cash-team/yalaa-cash` |
| Branch | `release/store-offers-and-customer-redesign` |
| Root Directory | `landing-page` |
| Build Command | empty (if the form insists: `echo "static site"`) |
| Publish Directory | `.` |
| Auto-Deploy | **Off** (deploy manually) |
| Pull Request Previews | **Off** |
| Plan | Free (static sites count against the workspace's included bandwidth) |

The APK is **not** served by Render: it comes from GitHub Releases, so the site itself stays small (about 0.35 MB per first visit) and the 5 GB workspace allowance is not spent on the 54 MB file.

Optional response headers (Render dashboard > Headers): `Cache-Control: public, max-age=31536000, immutable` for `/assets/*`.

## Before and after deploying

- `og:image` is intentionally still the relative `assets/img/og.png`. Once the final Render URL is confirmed, change it (and add `og:url`) to the absolute address so link previews work.
- `landing-page/` contains only public site files. The maintenance files (this README and `tools/`) live in `docs/landing-page/` and are not part of the Render publish folder. `landing-page/downloads/yalla-cash.apk`, if present locally, is git-ignored, unreferenced and never published.
- New Customer release: publish a new GitHub Release with a `yalla-cash.apk` asset (the `latest/download` link follows automatically), then update the version/size note under the hero buttons in `index.html`.
