# FliXtended Changelog


## v4.3.9

A partial merge of upstream FlixQuest 4.3.0, with our Firebase setup kept
intact. Upstream 4.3.0 moved accounts, sync, settings and notifications to
its own Laravel backend — we did not take that path, so everything below
runs on Firebase exactly as before.

### ✨ Experience

- **Tablet side rail** — large screens (600dp and up) get a side rail
  layout.
- **Cleaner screens** — server status and update screens use the shared
  content width, and changelog headings render bold with no bullet dot,
  bullets as hyphens.
- **More languages polished** — English, Arabic, Spanish and Hindi
  updated with the new keys (hold speeds, See-all labels,
  subtitle-formats notice).

### 🎬 Watching

- **Hold-to-speed gestures** — long-press a side of the player (controls
  hidden) to speed up or slow down while you hold, with a speed pill and
  restore on release. Speeds are configurable in settings.
- **Keep-screen-on, done right** — playback wake-lock moved to a
  dedicated service for both the main player and live TV.
- **Subtitle picker** — restricted to `.srt`/`.vtt`, with a fallback for
  older Android.
- **Movies remember their provider** — if you switch a movie to Nalanda
  (or any other provider), the next time you open that movie it starts
  from that provider instead of restarting from the top of the list. The
  choice is remembered per movie, even across restarts. Series already
  had this feature; movies now match.
- **Trailers** — YouTube trailer filtering and launching, cleaned up.

### 🛋️ Big Screen

- **See-all screens** — trending, popular and top-10 rows on TV now open
  proper paged grids.

### 📥 Offline

- **Nalanda downloads fixed** — Netmirror serves signed MP4 files, but
  the download flow only understood HLS/DASH manifests and treated
  everything else as HLS, so it died on audio inspection. The flow now
  recognises single-file progressive streams, skips the audio-track
  sheet for them (the audio is already inside the file), and saves the
  whole MP4. HLS and DASH downloads behave exactly as before.
- **Downloads remember your spot** — stop a downloaded movie midway,
  close the app, reopen the download, and it picks up at the same spot.
  Finish past 85% (or let it finish) and the saved spot clears, so the
  next open starts at 0 — the same rule streaming already uses.
- **Hidden HLS segments** — segments tucked inside images (disguised
  segments) are now unwrapped for downloads.

### ⚙️ Behind the Scenes

- **New TMDB layer** — the app's TMDB calls now run on a dedicated
  client with proxy routing and caching. Our Cloudflare Worker stays the
  TMDB route, so behaviour on Jio is unchanged; this is groundwork that
  keeps TMDB loading reliable.
- **Scraper on the same network layer** — provider results now load
  through the same Dio network client as TMDB, replacing the old
  plain-HTTP calls. Every provider, the full-list fallback, and subtitle
  pre-downloads stay exactly as they were — just one shared layer
  instead of two separate ones.


## v4.3.8 (2026-10-24)

The first release built on the new lavender-and-gold identity. It merges every
upstream FlixQuest change since v4.3.7 (v4.2.2 and v4.2.3) with all of our own
work from the beta cycle — except the pieces we deliberately left out (see
below).

### Our changes (per beta, newest first)

**beta+34 (2026-10-24)** — the branding beta. See **Branding** below.

**beta+25 (2026-10-23)** — download audio-track selection
- When a movie or episode has more than one audio track (for example the
  Hindi/Tamil/Telugu/Malayalam dubs on Dholavira), the download screen now
  asks which language to save after you pick a resolution.
- Streams with only one audio track download exactly as before — no extra
  screens, no behavior change.

**beta+24 (2026-10-18)**
- The provider list now opens in a fixed, sensible order on fresh installs:
  Zeila first, then Abyssinia, Gura, Karamara, followed by our direct
  providers (Nalanda, Hampi, Dholavira) and the rest of the catalog.
- Your preferred subtitle language is now auto-selected when you switch
  providers mid-playback (the setting existed before but was never applied).
- Sticky provider per series: if you switch a show to Karamara and hit next
  episode, it stays on Karamara instead of restarting from the top of the
  list. The choice is remembered per series, even across restarts.

**beta+23 (2026-10-18)** — TheIntroDB v4 migration
- Skip-intro, recaps and credits keep working on the new v4 API (the old v3
  endpoints are being retired upstream).

**beta+22 (2026-10-18)** — first test build of the v4.2.2 merge
- Direct providers renamed to their new identities: Nalanda (was NetMirror),
  Hampi (was Castle), Dholavira (was MX Player).

*Note: versions +26 through +33 have no separate code changes in the history —
the number stepped straight from +25 to +34. The branding test APKs built on
Oct 24 (beta33/beta34) are all contained in the +34 branding commit.*

### Upstream FlixQuest 4.2.3 (by Beamlak)

Merged in full except the items listed under "Deliberately left out".
- **Choose your audio for downloads** — pick a soundtrack before downloading
  movies or episodes with multiple audio tracks.
- **Do Not Disturb while streaming** — optional setting (Android 10+) that
  quiets notification sounds and call banners during playback. Off by default.
- **Live TV improvements** — DLHD's updated streaming loader with
  playlist-token renewal, and faster channel starts (Player 1 first, backups
  discovered after playback begins).
- **Safer progress saving** — watch progress is saved in the background so it
  no longer gets lost when you leave the player quickly.
- **Automatic TMDB proxy** — the app now probes direct TMDB connectivity and
  only routes through a proxy when direct access fails, re-checking on
  network changes. (FliXtended keeps its Cloudflare Worker as the TMDB
  route, so behavior here is unchanged.)
- **Playback feedback prompt** — an occasional, optional "how was the
  stream?" prompt (at most once every few days) plus silent diagnostics to
  help track down buffering and audio issues.
- Analytics for streaming events moved from Firebase to the existing Mixpanel
  setup. No visible change.

**Deliberately left out of v4.3.8:**
- *Ad-blocker enforcement* — upstream stops playback and shows a
  "turn off your ad blocker" message when a blocker is detected. FliXtended
  does not do this: if you use an ad blocker, that's your choice.
- *Download link-recovery overhaul* — upstream's machinery for recovering
  expired download links was not taken; the download flow is otherwise
  unchanged.
- *In-player audio-track removal* — upstream 4.2.3 removed audio-track
  switching from the player; we kept it.

### Upstream FlixQuest 4.2.2 (by Beamlak)

- **My Sports** — pick your favourite sports and see them first in Live TV;
  sport grouping is more accurate.
- **Better recovery** — Retry works again, expired movie/episode links can
  refresh at your saved position, and streaming waits for your connection
  instead of giving up while offline.
- **Player polish** — Live TV keeps the screen awake, PiP hides menus and the
  next-episode overlay, and playback makes fewer background requests.
- **Android TV polish** — minor UI visibility and experience updates,
  per-device-CPU APK downloads on the update screen, and a Telegram channel
  invite with QR code.

### Branding

- New **ribbon "F" logo** across the app: launcher icons (all densities),
  TV banner, splash screens, and in-app marks. The old FlixQuest-derived
  marks are retired everywhere.
- **Lavender + gold theme** is now the default: lavender primary (selected
  category chips, active bottom-nav icon) with gold accents (badges).
  Your own color choice and Material You theming still override it — reset
  Settings → Custom color → Default to see the brand theme.
- **Stronger glass**: heavier frosted blur on the bottom nav bar and the
  scrolling home header, with a hairline edge highlight. Stays solid when
  reduced motion is on.
- Native splash screen follows the system theme (light/white in light mode,
  black in dark mode).
