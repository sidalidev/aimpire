# Privacy policy

AImpire has no account, no analytics, no crash reports and no ads. This page lists everything that can leave your
device. The same list is in the app: Settings, About AImpire, What leaves your device.

## On the Mac

- **Your session logs**: the local server reads them in `~/.claude` on this Mac, read-only, and never sends them
  anywhere. AImpire never writes, moves or erases anything there.
- **Update check**: at launch, then once a day, the game asks `https://aimpire.sidali.dev/update.json` whether a newer
  version exists. It sends nothing about you. The server sees your IP address. You can turn it off in Settings.
- **Sync chain** (only if you create one): the state of your Empire goes to the relay (by default
  `aimpire.sidali.dev`, run by the developer; you can run your own), end-to-end encrypted, every few seconds while
  AImpire runs. In discreet mode (H), names, paths and titles are removed before encryption. The relay sees: a random
  chain id, message sizes, times, and your IP address while connected. It never sees the content.
- **Detailed voices** (off by default): only if you turn them on and set your own ElevenLabs key, the start of a
  session's latest request or reply (120 characters at most) goes to ElevenLabs over HTTPS, with your key, so a
  villager can say it. A sentence already spoken is cached on this Mac and not sent again.
- **Nothing else**. The local server listens on 127.0.0.1 only and requires a local token for every action.
  Notifications are shown by macOS on this Mac only and hold the village name and the kind of signal, never the
  content. The server log holds metadata only (counters, durations), never session content.

Your data lives in `~/Library/Application Support/AImpire/` (progress, saves, settings, voice cache, sync chain keys)
and the game settings in `~/Library/Application Support/Godot/app_userdata/AImpire/`.

## On Android

- **Sync chain**: the phone reads the state of your Empire from the relay given at pairing and sends it a few
  commands (claim, build, discreet mode), end-to-end encrypted. The relay sees: a random chain id, message sizes, times,
  and your IP address while connected. It never sees the content.
- **Update check**: same as on the Mac.
- **Nothing else**. Settings and the chain key stay in the app's private storage. Android backup is turned off.
  The only permission is Internet.

## Erase everything

Settings, About AImpire, Erase everything (type ERASE to confirm).

- On the Mac: the data folder and the game settings are erased, the sync chain is deleted from the relay, and AImpire
  quits. Nothing in `~/.claude` is ever touched.
- On Android: settings, the chain key and downloaded updates are erased, and the phone leaves the chain. The chain
  belongs to the Mac: delete it there to erase it from the relay right away, otherwise the relay erases it 30 days after
  the Mac stops publishing.

## The relay

The relay (`relay/` in the source code; the same code runs at `aimpire.sidali.dev`) keeps, for each chain, the latest
encrypted state and a small queue of encrypted commands. Its log lines hold the method, the path, the status, the
duration and the first 6 characters of the chain id, never an IP address or content. A chain without an update for 30
days is erased.

## Contact

contact@sidali.dev
