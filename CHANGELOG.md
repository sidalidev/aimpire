# Changelog

## 0.8.0 (2026-10-27): roman gold, light and dark
- New icon: a rounded temple drawn in dark ink on roman gold, flat. Android has an adaptive icon with a monochrome layer
  for themed icons; the Mac icon is redrawn at every size with macOS corners.
- The interface takes the app's colour, roman gold, and follows the system theme: cream in light mode, deep fir green in
  dark mode. The theme is read at launch. Text contrast meets WCAG AA in both themes (dark ink on gold 4.7:1, body text
  13.9:1 on cream and 15.8:1 on dark green).
- Everything is flat and rounded: no gradient, no gold border, sheets and cards with 22 to 24 dp corners, buttons with
  14 dp corners, round switches, rounded check boxes and radio buttons, a rounded close cross, round markers on the small
  map. The gradient behind the top bar is gone: the resource bar and the status line are pills of their own.
- New interface fonts: Bricolage Grotesque for titles, Figtree for text (both OFL). The world keeps Cinzel for the names
  of villages, the Forum and the bubbles: its carved capitals are those of Roman inscriptions.
- One primary action per screen in roman gold with dark text (Join, Claim, Create a sync chain); the other buttons are
  tinted. Toasts are inverted cards. The relay banner is honey with dark text. Village names start with a capital in
  the interface.
- The Mac gets the same look: top bar in a pill, panels, settings, check boxes, sliders, drop-down menus and dialogs.
- Android: version code 10.

## 0.7.0 (2026-10-25): the phone in portrait
- Android: AImpire is now held in portrait, like a city builder on a phone. Turning the phone changes nothing. The Mac
  does not change (landscape window, picture in picture, keyboard shortcuts).
- Camera on the phone: fixed angle. One finger moves the map and the ground stays under the finger, with inertia and a
  soft edge at the border of the Empire. Two fingers pinch to zoom about the point between them, from a close view to
  the whole Empire. Double tap frames a village, the Forum or the whole Empire. A tap picks the nearest building within
  reach of a thumb and opens its sheet at the bottom.
- Interface for one hand: resources at the top, a bar at the bottom (Cockpit, Villages, Senate, Settings) with badges,
  sheets that slide up from the bottom and close with a swipe down, the "x" or the back gesture. Safe areas are
  respected (camera hole, gesture bar), text is 16 sp at least and every touch target 48 dp.
- Cockpit sheet with Now, Today, Week and Journal tabs; Senate sheet (treasury, orders, monuments); Villages sheet (small
  map and list); Settings sheet with Discreet mode first and choices as buttons instead of drop-down menus. About and
  pairing fit the screen and stay above the keyboard.
- Smoothness: 60 frames per second while a finger touches the screen, the map glides or a sheet moves, 30 at rest
  ("Adaptive", the default). "Battery saver" keeps 30, then 15 after 20 s without a touch. The old frames per second
  setting is not carried over.
- Haptic feedback through the system: it follows the system setting and needs no permission.
- Settings on the phone: switches and radio rows instead of small check boxes, gold sliders. Toasts have a background so
  they stay readable over a sheet.
- Android fixes: the lake no longer shows as a white patch with the OpenGL renderer; one back gesture now goes back one
  step (a single gesture could count twice and quit the app); the haze no longer veils the whole Empire when zoomed out.
- Android: version code 9.

## 0.6.0 (2026-10-24): About, what leaves your device, erase everything
- New About screen, in Settings on the Mac and on Android (also on the pairing screen): our principles, version and
  what's new, last security review, signing certificate read from the installed APK on Android, report a security
  issue, privacy policy and contact.
- New "What leaves your device" screen: each piece of data that can leave, where it goes and whether it is encrypted.
- New "Erase everything", confirmed by typing ERASE. Mac: the data folder and the game settings are erased, the sync
  chain is deleted from the relay, then AImpire quits. Nothing in `~/.claude` is ever touched. Android: settings and the
  chain key are erased and the phone leaves the chain.
- Repository: SECURITY.md, PRIVACY.md, threat model, internal security review of 24 Oct 2026, expected permissions.
- CI: fails on an unexpected Android permission, a long dash, an authorship marker or a personal path, a security
  review older than 6 months, or a version without a changelog entry.
- Android: version code 8.

## 0.5.2 (2026-10-24): English villager voices, consistent encryption output
- Villager voices are now in English.
- Encryption output is now identical on every machine (CI fix).
- Android: version code 7.

## 0.5.1 (2026-10-24): verified updates, English interface
- macOS: the game now downloads the update itself, checks its SHA-256 against the published manifest and only then
  shows it in Finder. A file that does not match is deleted. Manifest entries without a valid SHA-256 are ignored.
- The whole interface is now in English: game, settings, sync chain, phone mode, notifications, reports, server and
  relay messages. The language setting is gone.
- Android: version code 6.

## 0.5.0 (2026-10-20): updates
- The game (Mac and Android) reads `https://aimpire.sidali.dev/update.json` at launch, then once a day. Setting "Check
  for updates", on by default. A newer version shows a toast and an "Update" button at the top right and in Settings.
- Mac: the button downloads the zip in the browser. Android: the browser downloads the APK, then Android offers to
  install it.
- Relay 0.5.0: `GET /update.json` and `GET /download/<file>` served from a read-only folder, with strictly checked file
  names.
- `tools/release-macos.sh` and `tools/release-android.sh` publish by themselves: SHA-256, merged update.json, copy to the
  server, GitHub release.

## 0.4.0 (2026-10-19): fixes from the review of the sync chain and Android
Chain format changed: the id now derives from W. Chains created with 0.3.0 must be deleted and created again.
- Discreet mode is an allowlist (`daemon/blur.js`): no journal, registry, paths or client names in the served or
  published state; village ids are pseudonymised; journal, report, digest and goals are hidden on the Mac screen.
- Freshness is measured with the Mac's authenticated timestamp; the last timestamp is kept in `chaine.cfg`, so the relay
  can neither freeze the display without a banner nor bring back an old state after a restart.
- Commands: anything older than the server start, or older than the last applied setting, is refused (replay after a
  restart, reordering by the relay).
- The chain secret is hidden by default in the Mac settings, never shown in discreet mode, and cleared from the
  clipboard after 30 s.
- Relay 0.4.0: blobs capped at 256 KiB, id checked against W when claimed, new ids counted per /48 in IPv6 and capped at
  100 per day, memory and process limits in the compose file. The Mac retries every 10 min after a 401.
- States padded to a 16 KiB step (gzip FEXTRA field); publications caused by a change are at least 10 s apart.
- Phone: responses capped before decryption, relay address parsed (no `#`, no `?`, http only on a local network),
  1 to 5 s pause after a long-poll that did not wait, banner with two clocks, deleted chain detected, envelope version
  checked, commands dropped after 60 s or refused when the Mac is silent, double back gesture to quit, safe area,
  scale recomputed.
- Android: OpenGL by default (Vulkan as an option), nature textures VRAM-compressed with mipmaps (1024 px at most),
  unused models left out of the export (APK 42 MB instead of 56), vertical sync kept, 15 frames per second after 20 s
  without a touch, "Minimal" quality without shadows, sky without radiance map, HUD redrawn only when it changes.
- Double tap: the panel opened by the first tap closes again.

## 0.3.0 (2026-10-19): sync chain and Android client (not published)
- Encrypted relay, Godot phone client, pairing by link or 12 words, signed Android export.

## 0.2.0 (2026-10-16): hardened local server and Roman kit
- Hardened local server: 127.0.0.1, token, no CORS, data in Application Support, atomic writes.
- Procedural Roman kit: buildings, walls, Forum, monuments, Mediterranean vegetation, Roman outfits.
- Lasting daily ledger, rebalanced economy, treasury since installation, prices in working days.
- Attention signals (question, permission, end of turn, error, silence), cockpit (Tab), macOS notifications.
- Actions on a session, digest, daily summary (R), Senate report (W), journal (J), discreet mode (H).
- CC0 sounds (Kenney, OpenGameArt), CC0 music, embedded Cinzel and Inter fonts.
- Exportable macOS app with an embedded server (`tools/release-macos.sh`).
