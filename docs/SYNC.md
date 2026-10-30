# Sync chain: watching the Empire from a phone

Goal: watch AImpire from an Android phone, including one without Google services, through a sync chain in the spirit of
Brave Sync, without the relay being able to read or forge anything. The Mac stays the only source of truth: the phone
watches and sends a few commands, it computes nothing.

```
Mac (daemon/sync.js)                          relay (relay/)                          phone (Godot client)
  served state --gzip--encrypt--PUT /blob -->  one opaque blob per id   <-- GET /blob?wait=25 -- decrypt, display
  apply <--decrypt-- GET /cmd <-------------   queue of 20 commands per id <-- POST /cmd ------- encrypt a command
```

The default relay is `https://aimpire.sidali.dev/`, run by the developer with the code in `relay/`. Any relay running
that code works (section 4).

Reference files:

| Role | File |
|---|---|
| Node cryptography (pure functions) | `daemon/sync-crypto.js`, wordlist `daemon/bip39-english.js` |
| Godot cryptography (the same) | `godot/sync_crypto.gd`, wordlist `godot/assets/bip39-english.txt` |
| Shared vectors | `docs/SYNC-VECTEURS.json`, produced by `daemon/scripts/genere-vecteurs-sync.js` |
| Tests | `cd daemon && node --test`; `godot --headless --path godot -s tests/test_sync_crypto.gd` |

Both implementations must produce exactly the same bytes: any change to the format goes through the vector generator
first, then through both tests.

The field names of the wire format (`etat`, `annexes`, `reclamer`, `construire`, `reglage`, `flou`...) are French. They
are part of the protocol and stay as they are.

---

## 1. Chain

A chain is a **16-byte secret S** (128 bits) drawn by the Mac with a cryptographic generator (`crypto.randomBytes(16)`).
Everything else (id, write token, keys) is derived from it; there is no account.

Creation: game settings on the Mac (Esc), "Create a sync chain", after choosing the relay address. The Mac then shows S
in three equivalent forms:

1. **QR code** holding the link below (byte mode, error correction M, smallest version that fits, 3 or 4 in practice).
2. **Link** `https://aimpire.sidali.dev/#s=<base64url(S)>`: base64url without padding (RFC 4648 section 5), 22
   characters. The secret is in the fragment (`#`), which browsers never send to the server. The origin of the link
   names the relay to use; a link `http://127.0.0.1:7701/#s=...` points to a local test relay.
3. **12 BIP 39 words** (official English list, 2048 words, SHA-256 of the file
   `2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda`), exactly like a Bitcoin wallet: the 128 bits of
   S followed by the first 4 bits of SHA-256(S), cut into 12 groups of 11 bits (index in the list). Input ignores case
   and spaces; an unknown word or a wrong checksum is refused. With words, the relay is the default one unless the
   phone sets another (section 7).

One chain per Mac (one at a time). To revoke a lost phone: "Delete the chain", then create a new one (new S, so new id
and new keys). The old blob is erased from the relay on the way.

**What the relay receives**: the id (32 hex characters), the write token W (proves knowledge of S, cannot decrypt),
opaque blobs, their sizes (to 16 KiB, see section 3) and times, the IP address. Never S, never K_enc or K_mac, never
plaintext.

## 2. Keys

Notation: `HKDF(S, info, n)` = HKDF-SHA256 (RFC 5869) with an **empty salt** (so 32 zero bytes at extraction), `info` in
UTF-8, `n` output bytes. `||` is byte concatenation.

| Name | Definition | Size | Use |
|---|---|---|---|
| W (write token) | `hex(HKDF(S, "aimpire-write", 32))` | 64 lowercase hex chars | `Authorization: Bearer <W>` on the routes that write or delete |
| id | `hex(SHA-256("aimpire-id" \|\| W as ASCII))[0:32]` | 32 lowercase hex chars | names the chain to the relay (`X-AImpire-Id`) |
| W fingerprint | `hex(SHA-256(W as ASCII))` | 64 hex chars | the only thing the relay keeps of W |
| K_enc | `HKDF(S, "aimpire-enc", 32)` | 32 bytes | AES-256-CBC |
| K_mac | `HKDF(S, "aimpire-mac", 32)` | 32 bytes | HMAC-SHA256 |

The relay learns W at the first write (first `PUT /blob` for an unknown id), **checks that the id is derived from that
W** (otherwise 401), stores its fingerprint, then compares the fingerprint of every W received in constant time. As
the id is a hash of W, knowing an id does not allow claiming it, even after it is purged (30 days without a write): it
takes W, so S. (Up to 0.3.0 the id came from a proof `HKDF(S, "aimpire-proof", 16)` the relay could not check; chains
created before 0.4.0 must be created again.) The phone knows S, so it could compute W; it does not use it in v1 (it
only writes to the command queue, which needs only the id).

Vectors for `S = 000102030405060708090a0b0c0d0e0f` (from `SYNC-VECTEURS.json`):

```
id      b054a86b0e7d1a0329b8dcb1939cf07e
W       86724ad799f080ed0a64e79b47908a23f5a06208599643adf6c806ab0f06bdcc
K_enc   11242c6583aef351d05dbd90d508b58a77cea8b0cb553c2f2b7af43fad3c1d5b
K_mac   8aeb7857c1e32b34c9e9118f28bcf25921d504b7ce5cd6347d19e38690151163
words   abandon amount liar amount expire adjust cage candy arch gather drum buyer
link    https://aimpire.sidali.dev/#s=AAECAwQFBgcICQoLDA0ODw
```

## 3. Blob format

Godot has no AES-GCM: encrypt then MAC.

```
byte 0           version = 0x01
bytes 1..16      iv: 16 random bytes, new for every blob
bytes 17..n-33   ciphertext = AES-256-CBC(K_enc, iv, PKCS7(plaintext)), a multiple of 16, at least 16 bytes
last 32          mac = HMAC-SHA256(K_mac, iv || ciphertext)
```

- Size = 1 + 16 + 16 x (floor(len(plaintext) / 16) + 1) + 32, at least 65 bytes.
- Reading: refuse if version is not 1, length below 65 or (length - 49) not a multiple of 16; **check the mac in
  constant time before any decryption**; then decrypt and check the PKCS7 padding. Any error rejects the whole blob.
- The relay can check the shape (version, lengths) without a key; it can neither read nor produce a valid mac.
- The version byte is not covered by the mac (the mac covers iv || ciphertext); this has no effect as long as only
  version 1 is accepted. A version 2 must include the version byte in the mac.

**Plaintext**: UTF-8 JSON, possibly gzip compressed (RFC 1952). The reader decompresses when the plaintext starts with
`1f 8b` (JSON starts with `{`), with a 16 MiB cap after decompression. The Mac always compresses the state (measured:
125 KB of JSON for 15 villages, 21 KB gzipped; 27 KB of JSON in discreet mode); the phone only sends raw JSON (commands
of a few dozen bytes).

**Padding**: the gzip of a state is padded to `16384 x n - 1` bytes before encryption, which gives a ciphertext of
exactly `16384 x n` bytes (PKCS7 adds 1 to 16 bytes). The padding goes in the FEXTRA field of the gzip header
(`FLG.FEXTRA` flag, one `AP` subfield filled with zeros, RFC 1952 section 2.3.1), which every gzip decoder skips: the
decompressed plaintext is unchanged and the reader has nothing special to do (vector `blob_bourre`, step reduced to 256
bytes). The relay therefore only follows the size of the state to 16 KiB.

There is no associated data (AAD): states and commands are told apart by the `type` field of the plaintext.

### State envelope (Mac to phone)

```json
{
  "type": "etat",
  "v": 1,
  "ts": 1760000000000,
  "etat": { "...": "exactly what GET /state serves at the same moment (blurred if discreet mode is on)" },
  "annexes": {
    "rapport": { "jour": "text of GET /rapport?periode=jour", "semaine": "text of GET /rapport?periode=semaine" },
    "journal": [ "the latest 60 entries of GET /journal" ],
    "digest": { "...": "GET /digest" },
    "commandes": [ { "nonce": "...", "ok": true, "erreur": "", "t": 1760000000000 } ]
  }
}
```

- `v`: version of the state schema (1). The Mac raises it at every incompatible change; a phone that receives another
  version shows nothing and asks to update the app.
- `ts`: the Mac clock in milliseconds at encryption time, authenticated by the mac. The phone refuses any state whose
  `ts` is lower than the last one accepted, and keeps that `ts` in `user://chaine.cfg` (`[reception] dernier_ts`,
  written at most every 30 s and when the app goes to the background): even after a restart of the app, the relay
  cannot bring back an older state. The same `ts` is accepted once per launch (to have something on screen).
- `ts` also measures freshness: the Mac republishes at least every 60 s, so a state older than 2 minutes (phone clock)
  means a Mac that no longer publishes. `X-AImpire-Maj` (relay clock, not authenticated) can only make that warning
  worse, never hide it.
- In discreet mode (`privacy = "flou"`), `etat` goes through an **allowlist** (`daemon/blur.js`): only the fields the
  client shows, names replaced ("Village I", "Session 2", "task"), requests, replies, branches and MCP tool names
  removed, village ids replaced by stable pseudonyms (`v` + 10 hex characters, HMAC of the local token; only the Mac
  can map them back to the real village for `reclamer`). No journal, no ledger, no orders, no locations, no goal
  proposals. `rapport`, `journal` and `digest` are `null`: they do not leave the Mac. The phone shows "Unavailable in
  discreet mode". On the Mac screen too, in discreet mode, `/journal` only shows event types, `/rapport` is unavailable
  and goals cannot be set.
- `commandes`: result of the latest 10 commands received from the phone, so it can show feedback (section 6).

### Command envelope (phone to Mac)

```json
{ "type": "cmd", "ts": 1760000000000, "nonce": "<32 random hex characters>", "action": "construire", "id": "colisee" }
```

See section 6 for the actions and their fields.

## 4. Relay and routes

Folder `relay/`: Node 22, no dependencies, one HTTP process. It only knows ids, W fingerprints and opaque blobs.
License: AGPL-3.0-only (`relay/LICENSE`).

### Running your own

- Plain Node: `PORT=7701 AIMPIRE_RELAY_DATA=/path/to/data node relay/server.js`, behind any HTTPS reverse proxy.
- Docker: `relay/Dockerfile` (`node:22-alpine`, non-root user). `deploy/relay-compose.yml` runs it behind Traefik with
  `read_only: true`, `no-new-privileges`, a named volume on `/data`, `mem_limit: 256m` and `pids_limit: 64` (500 chains
  x 256 KiB fit in 128 MiB), and a `wget` healthcheck on `/health`. Set `AIMPIRE_RELAY_HOST` to your host name.
- Variables: `PORT` (7701), `AIMPIRE_RELAY_DATA` (`/data`; without it, memory only), `AIMPIRE_TRUST_PROXY=1` (behind a
  proxy, the IP comes from `X-Forwarded-For`, last hop), `AIMPIRE_RELEASES_DIR` (optional folder served on
  `/update.json` and `/download/<file>`). The 25 s long poll stays under the default read timeout of Traefik (60 s).

### Storage

- In memory: `Map<id, { fingerprint, blob, etag, updated, cmds: [] }>`.
- On disk: **one file per id**, `/data/<id>.json` = `{"empreinte": "<hex>", "maj": <ms>, "blob": "<base64>"}`, written
  atomically (temporary file, fsync, rename). Reloaded at start.
- The command queue lives in memory only (lost on restart, harmless: the phone sends again).
- An id without a `PUT` for 30 days is purged (memory and disk). Global cap: 500 ids (beyond, 507).

### Common headers

- `X-AImpire-Id: <id>` on every data route; 400 if it is not `^[0-9a-f]{32}$`.
- `Authorization: Bearer <W>` where stated; 401 if missing or if its fingerprint does not match.
- Error responses in JSON `{"error": "..."}`; `Cache-Control: no-store` everywhere; no CORS (no browser client).

### Routes

| Route | Headers | Body | Responses |
|---|---|---|---|
| `PUT /blob` | Id, Authorization | blob (bytes, 256 KiB at most) | 200 `{"ok":true,"etag":"..."}`; 400 malformed blob; 401 (including an id not derived from W); 413 too large; 429 |
| `GET /blob` | Id, optional `If-None-Match` | | 200 blob + `ETag`; 304 unchanged; 404 unknown id; 429 |
| `GET /blob?wait=25` | Id, `If-None-Match` | | as above, but waits up to `wait` seconds (capped at 25) for a change if the ETag matches |
| `DELETE /blob` | Id, Authorization | | 200 `{"ok":true}` (blob, queue and file erased); 401; 404 |
| `POST /cmd` | Id | blob (bytes, 4 KiB at most) | 202 `{"ok":true}`; 400; 404 unknown id; 413; 429 queue full or rate |
| `GET /cmd` | Id, Authorization | | 200 `{"cmds":["<base64>", ...]}` in arrival order, then the queue is emptied; 401 |
| `GET /health` | | | 200 `{"ok":true,"version":"...","ids":<n>,"uptime":<s>}` |
| `GET /` | | | static HTML page (below) |

Details:

- **First write**: `PUT /blob` on an unknown id checks `id == hex(SHA-256("aimpire-id" || W))[0:32]`, then creates the
  entry with the fingerprint of the received W (counts in the quota of 10 new ids per IPv4 or per IPv6 /48 per day, and
  in the global cap of 100 new ids per day). Later writes require the same W.
- **ETag**: `"` + `hex(SHA-256(blob))[0:32]` + `"`, computed by the relay. `GET /blob` returns it in `ETag` and adds
  `X-AImpire-Maj: <ms>` (time of the last `PUT`, relay clock, used to show "Mac silent since...").
- **Long poll**: if `If-None-Match` matches the current blob, the request is held until the next `PUT` for this id
  (immediate 200) or for `wait` seconds (304). At most 4 simultaneous waits per id and 200 in total; beyond, an
  immediate 304 (the phone then waits 1, 2 then 5 s before trying again, section 7). A client disconnection frees the
  wait.
- **Command queue**: 20 at most per id. Queue full: 429, the command is not added (old ones are not dropped). The relay
  only checks the shape of the blob (section 3). Anyone who knows the id can fill the queue with invalid commands: a
  possible denial of service, not a breach (the Mac rejects anything without a valid mac).
- **Rate limits** (sliding window, in memory, 429 with `Retry-After`):
  - 600 requests per IP over 5 minutes, all routes together (a Mac and a phone on the same Wi-Fi make about 220);
  - 1 `PUT /blob` per second per id;
  - 30 `POST /cmd` per minute per IP;
  - 10 new ids per day per IPv4, or per /48 in IPv6 (a /64 costs nothing to whoever has a /48: 65,536 /64s);
  - 100 new ids per day in total.
- **Logs**: one line per request `method path status duration id`, the id cut to 6 characters followed by an
  ellipsis. Never W, never the body, never the IP address.
- **`GET /`**: static page without any script, served with
  `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'`. It explains that the link opens in the
  AImpire app ("Paste" on the pairing screen) and never reads the fragment. Accepted limit: a link opened in a browser
  hands the secret to the page served by that domain; a compromised relay could slip a script into it. The 12 words,
  typed in the app, do not have that risk.

## 5. Mac side (daemon/sync.js)

Enabled by `<data folder>/config.json` (written in mode 0600 by `writeAtomic`):

```json
{ "privacy": "normal", "sync": { "enabled": true, "relay": "https://aimpire.sidali.dev/", "secret": "<S in hex, 32 characters>" } }
```

Send loop, every 3 s:

1. Build the state envelope (section 3) from the served state (`stateJson`, already blurred in discreet mode) and the
   annexes.
2. Compute `h = SHA-256(JSON of { state without tick, peak and the buildings' ago, annexes without digest.since })`:
   `tick` changes at every scan round and would resend everything, as would `peak` (recomputed food peak) and `ago`
   (seconds since the last line of each session, refreshed by the heartbeat). Command results count: the phone sees its
   answer quickly, and a state is republished at once after an applied command.
3. `PUT /blob` if `h` changed (at most once every 10 s: during active work the hash changes at every round), or if the
   last send is older than 60 s (heartbeat: its authenticated `ts` is the only proof of freshness the phone accepts).
   An applied command republishes at once. The gzip is padded to the 16 KiB step (section 3).
4. Network failure: increasing wait 3, 6, 15, 30, 60 s; 401: the relay refuses the token, error shown in the settings
   and a new try in 10 min (no final stop: a relay that recovers finds the chain again); 413: state too large, error
   shown.

Command loop, every 3 s: `GET /cmd`, then for each blob `decryptJson`, validation (section 6) and application with
**the same functions as the local routes** (`/reclamer`, `/construire`, `/reglage`), shared with `server.js`. The
result is added to `annexes.commandes` and an event `{type: "telephone", text}` goes into the game journal.

Local routes (127.0.0.1, local token required because they reveal S):

| Route | Effect | Response |
|---|---|---|
| `GET /sync` | chain status | `{"enabled":false}` or `{"enabled":true,"relay","id_court","lien","mots":[12],"qr":{"taille":n,"modules":["0110...", ...]},"dernier_envoi":<ms>,"octets":<n>,"erreur":"","commandes":<n>}`; in discreet mode, `"masque":true` instead of `lien`, `mots` and `qr` |
| `POST /sync?action=creer[&relais=URL]` | draws S, stores it, starts the sync | as `GET /sync`; 409 if a chain already exists |
| `POST /sync?action=supprimer` | `DELETE /blob` on the relay (best effort), removes `sync` from config.json | `{"ok":true}` |

- Without `relais`, the server uses `AIMPIRE_RELAIS` if set, otherwise the default relay.
- `qr.modules`: one string of `0` and `1` per row, `taille` rows of `taille` characters, **without** quiet zone (Godot
  adds 4 white modules around and draws one square per module). The QR code is generated in Node, without dependency.
- Godot settings: "Relay address" and "Create a sync chain"; once created, the short id, the status ("Last sent 3 s
  ago, 32 KB") and "Delete the chain". The secret (QR, link with "Copy", 12 numbered words) is **hidden by default**
  behind "Show the secret": it hides again by itself after 60 s or when the menu closes, and it is absent in discreet
  mode (the server does not even serve it), so opening the settings during a video call never shows it. The copied link
  is removed from the clipboard after 30 s if it is still there (universal clipboard, histories).

## 6. Commands

The phone can do three things only. Actions that run code on the Mac (`POST /action`), goals and the festival stay on
the Mac.

| `action` | Fields | Local equivalent |
|---|---|---|
| `reclamer` (claim) | `village`: village id | `POST /reclamer?village=...` |
| `construire` (build) | `id`: monument id | `POST /construire?id=...` |
| `reglage` (setting) | `cle` = `"privacy"`, `val` = `"normal"` or `"flou"` | `POST /reglage?cle=privacy&val=...` |

Validation by the Mac, in this order (any failure is recorded in `annexes.commandes` with `ok: false` and ignored):

1. valid mac and readable JSON (otherwise the command is dropped without a trace: it does not come from a holder of S);
2. `type == "cmd"`;
3. `|now - ts| <= 10 min` (Mac and phone clocks);
4. `nonce` of 32 hex characters, never seen: the Mac keeps the nonces of the last 15 minutes (500 at most), which blocks
   any replay by the relay;
5. `ts` after the start of the Mac server: nonces only live in memory and the server restarts with the game, so an
   earlier command is refused ("sent before AImpire started on the Mac, send it again");
6. known `action` and valid fields;
7. for `reglage`: `ts` strictly greater than the last applied setting (`sync.dernierReglage` in config.json, also
   updated when discreet mode changes on the Mac). A relay that holds back "normal" and delivers it after "flou" cannot
   leave the Mac in normal mode, and a phone command older than a choice made on the keyboard does not undo it.

The phone shows "Sent to the Mac..." then the result when it sees its nonce in `annexes.commandes` (or "The Mac did not
answer" after 30 s; the command is then also removed from the send queue if it has not left). A command that could not
be dropped on the relay within 60 s is abandoned. If the Mac has not published for more than 2 minutes, nothing is
sent: "Mac offline: command not sent".

## 7. Phone mode and pairing

### Start

The Godot client enters **phone mode** if one of these is true:

- `user://chaine.cfg` exists and holds a valid chain;
- the app is started with a link (`--chaine=<link>` in the user arguments, handy to test from a second Mac);
- `OS.has_feature("mobile")`: without a chain, the pairing screen opens directly.

In phone mode no local server is started or queried (`net.on_failure` restarts nothing) and the local token is not
read.

`user://chaine.cfg` (private app storage on Android):

```ini
[chaine]
secret="000102030405060708090a0b0c0d0e0f"
relais="https://aimpire.sidali.dev/"
appairee_le=1760000000
```

### Receiving the state

1. `GET <relay>blob?wait=25` with `X-AImpire-Id` and `If-None-Match` (last ETag received), in a loop.
2. 200: `decrypt_json`, check `type == "etat"` and an increasing `ts`, then **the same rendering as `/state`** (the
   function of `main.gd` that handles `/state` is `_apply_state(s: Dictionary)`, called by both paths). Report,
   journal and digest come from `annexes` instead of the local routes.
3. 304 after a real wait: try again at once. A useless answer (304, or a state already seen) back in less than 2 s
   (relay waits all taken, a proxy that cuts): wait 1, 2 then 5 s; a 200 without `ETag`: at least 2 s between two
   requests. 404: "The Mac has not published anything yet" (try every 5 s); if a state of this chain was already seen,
   "Chain deleted on the Mac or expired: join your Empire again" (try every 60 s). Wrong mac or unreadable JSON:
   "Invalid chain" and nothing is shown. Network error: wait 1, 2, 5, 15 s.
4. Banner (under the status row, full width), two clocks: the last relay answer (phone side) and the `ts` of the state
   (Mac side). Phone offline or back from sleep: "Updating..." or the network error, followed by "Mac state from 14:32"
   ("yesterday 18:42", "17/10 18:42"), without blaming the Mac. Relay reached and state older than 2 minutes: "The Mac
   has not published for 12 min (AImpire closed, Mac asleep or off) · Mac state from 14:32".
5. Answers are capped before any decryption: 257 KiB for `GET /blob` (the relay refuses more than 256 KiB), 64 KiB for
   `POST /cmd`. A malicious relay cannot bring the app down by sending hundreds of MB.
6. In the background (`NOTIFICATION_APPLICATION_PAUSED`) the long poll stops; it resumes on return. No push
   notifications: a phone without Google services has no FCM, and the goal is watching, not alerting.

### Pairing screen

No camera in v1. Two ways:

- **Paste the link**: text field + "Paste" button (`DisplayServer.clipboard_get()`), `from_link`, relay taken from the
  link. To move the link from the Mac to the phone: the phone camera app on the QR code (it offers to copy the text), or
  "Copy" on the Mac then any trusted transfer.
- **Type the 12 words**: autocompletion on the BIP 39 list after 3 letters, `from_words`, default relay.
- **Custom relay** (folded "Relay ... change" field): empty, the relay of the link or the default one is used; filled,
  it replaces both. The address is parsed: no fragment (`#`), no query (`?`), no credentials (`@`), so pasting the
  pairing link there is refused (the secret would end up neither in `chaine.cfg` nor in the Android log); `https`
  everywhere, `http` only towards 127.0.0.1, localhost, 10.0.2.2 (emulator) and the private networks 10/8, 172.16/12,
  192.168/16, with a visible warning (the id and the traffic travel in clear). Useful when the Mac publishes to a local
  relay (`http://127.0.0.1:7701/`) that the phone reaches by another address: `http://10.0.2.2:7701/` from the Android
  emulator, the Mac's Wi-Fi address from a real phone. A link where only the host differs (`http://10.0.2.2:7701/#s=...`)
  works too without touching the field.

After validation: `user://chaine.cfg` is written, the short id is shown (first 6 characters, the same as in the Mac
settings, to compare by eye), first `GET /blob`. Phone settings: "Forget this sync chain".

### Touch and interface

Since 0.7.0 the phone is held in **portrait** (details, formulas and measures: `docs/MOBILE-PORTRAIT.md`).

| Gesture | Effect |
|---|---|
| drag one finger | move the map: the ground stays under the finger, inertia on release, soft bound at the edge of the Empire |
| pinch | zoom about the point between the fingers, from 18 to the view of the whole Empire (far limit from its extent) |
| tap | pick the building nearest to the finger (28 dp tolerance), otherwise the village; its sheet opens in peek |
| double tap | on a village: frame it; on the Forum: frame it; elsewhere: overview |
| back gesture | About, then pairing, then the open sheet, then the selection; with nothing open, a second gesture within 2 s quits |

Fixed angle (55 degree pitch, 30 degree horizontal field), no rotation with the fingers. The camera moves once per
frame.

- Resource bar at the top (numbers on 4 characters), status row below (title, "! N need you" which opens the cockpit,
  "Discreet" when discreet mode is on), chain status banner under the status row.
- Bottom bar: Cockpit, Villages, Senate, Settings, with badges (sessions waiting for you, rewards to claim, update).
  Each button opens a sheet that slides up from the bottom: close it by swiping it down, with its "x" or with the back
  gesture. The village sheet opens in peek (the map stays usable above).
- Cockpit: tabs Now, Today (daily summary), Week (weekly report), Journal. Senate: treasury, Senate orders ("Claim"),
  monuments ("Build"). Villages: reduced small map and list. Settings: discreet mode first, smoothness, quality,
  renderer, sounds, voices, updates, Phone section, About.
- "Claim", "Build" and discreet mode go through an encrypted `POST /cmd` instead of the local routes.
- Interface scale: one unit = one dp in both orientations (`density / min(width / 1280, height / 720)`, density =
  `screen_get_dpi() / 160` clamped between 1 and 3), recomputed when the window size changes; Android safe areas on the
  four edges (`DisplayServer.get_display_safe_area()`: camera hole, gesture bar); text at least 16 sp, touch targets
  48 dp.
- The HUD is redrawn only when a state arrives, when the open sheet changes and every 5 s (ages "... ago"), never during
  a gesture.
- "Performance" quality by default on mobile; a "Minimal (no shadows)" tier is offered (no shadows, no glow).
- Smoothness: 60 frames per second as soon as a finger touches the screen, the map glides or a sheet moves, and 1 s
  after; 30 at rest ("Adaptive", the default). "Battery saver": 30, then 15 after 20 s without a touch. Vertical sync
  stays on on phones. The 0.6.0 "Frames per second" setting is not carried over.
- Haptics through `View.performHapticFeedback` (system setting respected, no permission): button press, selection, edge
  of the world, sheet settled, command applied or refused.
- The sky provides neither ambient light nor reflections (`reflected_light_source = DISABLED`): its radiance map is not
  recomputed every frame.
- "Measure FPS (Android log)" setting: every 2 s a line readable with `adb logcat -s godot`, for example
  `FPS 60 cap 60 cam PINCH p50 16.6 p95 17.2 over25 0 max 18.9 draw 130 prim 210000 quality 2 driver opengl3 win (1080, 2340)`
  (cap, camera state, median and 95th percentile frame time, frames over 25 ms, the longest; on by default in a debug
  build or with `AIMPIRE_FPS`).
- **OpenGL ES 3 by default** on Android (`rendering/renderer/rendering_method.mobile="gl_compatibility"`): a failing
  Vulkan driver leaves Godot on a black screen before the first script, with no way to reach a setting (seen with the
  software Vulkan of the emulator). "Renderer" setting: OpenGL (default) or Vulkan (to try), written to
  `user://moteur.cfg`, which Godot reads at start (`application/config/project_settings_override`); applied at the
  next launch; if it hangs, clearing the app data goes back to OpenGL. No visual loss: the outlines (`post.gdshader`)
  only exist in Forward+.
- Portrait orientation (`display/window/handheld/orientation=5`, sensor portrait: the manifest says `USER_PORTRAIT`,
  which respects the rotation lock); a landscape window (large screen, split screen) keeps the same layout, capped at
  560 dp and centered.
- The small map is never on screen on a phone: a reduced copy lives in the Villages sheet.

## 8. Android export

- Export templates: Godot 4.7.2, installed from the editor (Manage Export Templates).
- `Android` preset in `godot/export_presets.cfg`:
  - `gradle_build/use_gradle_build=false` (so no custom manifest: no intent filter, the link cannot open the app
    directly in v1, hence the "Paste" button);
  - `architectures/arm64-v8a=true`, the others `false`;
  - `package/unique_name="dev.sidali.aimpire"`;
  - permissions: `permissions/internet=true` only (`docs/permissions.txt`, checked by the CI);
  - `screen/immersive_mode=true`, portrait orientation (since 0.7.0, `USER_PORTRAIT` in the manifest);
  - `include_filter="assets/bip39-english.txt"` (a text file, not an imported resource: without this filter it is
    missing from the package) and `exclude_filter` extended with `tests/*` and the nature models never loaded
    (`TwistedTree_*`, `Pine_*`, `Bark_TwistedTree*`, `Leaf_Pine_C.png`), for macOS too.
- Textures of `assets/nature` imported as compressed VRAM (ETC2 on Android, S3TC/BPTC on the Mac), with mipmaps, capped
  at 1024 px, normals in "normal map" mode: about 10 MB of VRAM instead of more than 110 MB, and no more shimmering of
  distant foliage. The Kenney palettes (`colormap.png`, 512 px) stay lossless: a compressed block would mix neighbouring
  colours. APK: 42 MB (56 MB before).
- Release keystore `~/.aimpire/release.jks`, created by `keytool` if missing (alias `aimpire`, RSA 4096, 10,000 days);
  random password in `~/.aimpire/keystore.properties` (0600), **never in the repository**; passed to the export through
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`.
  A keystore you create yourself signs with another certificate than the official releases (`SECURITY.md`).
- Godot editor settings, if the export asks for them: `export/android/java_sdk_path` (JDK 21, for example
  `/opt/homebrew/opt/openjdk@21`), `export/android/android_sdk_path` (for example `~/Library/Android/sdk`),
  `export/android/debug_keystore` (standard debug keystore).
- `tools/release-android.sh`: checks the keystore (creates it otherwise), exports
  `godot --headless --path godot --export-release "Android" build/AImpire.apk`, then
  `apksigner verify --print-certs build/AImpire.apk` (SDK build tools) and prints the size and the certificate
  fingerprint.
- Installation: from the GitHub releases, with Obtainium (README) or by opening the APK on the phone.

## 9. Threat model, in short

| The relay (or whoever controls it) can | It cannot |
|---|---|
| see the id, the sizes (to 16 KiB), the times, the IP addresses | read the state or the commands (AES-256 with K_enc) |
| delay, drop, erase blobs (denial of service) | forge a state or a command (HMAC with K_mac) |
| freeze the display (keep an old blob, answer 304, lie in `X-AImpire-Maj`) | hide it: the age comes from the authenticated `ts`, the "no longer publishes" banner shows after 2 min |
| replay an old state | get it displayed, even after an app restart (`dernier_ts` kept in `chaine.cfg`) |
| replay an old command | get it applied (10 min window, nonces already seen, nothing older than the Mac start) |
| reorder two settings | make the older one win (`ts` of the last applied setting, kept in config.json) |
| fill the command queue of a known id | get anything run other than claim, build, discreet mode |
| answer 401 to the Mac | stop the chain for good (new try every 10 min) |
| serve a script on `GET /` if the link is opened there | get anything from someone who types the 12 words in the app |

Claiming an id (after its purge, or before the first write) takes W: the id is a hash of it (section 2).

**Accepted leaks**: the size of the blobs (to 16 KiB: switching to discreet mode may still show if it changes step),
their times (work rhythm, a 60 s heartbeat while the Mac runs, silence when it is closed) and the IP addresses. Anyone
who knows an id can also take its 4 long waits or the 200 of the relay: the phone then waits (1, 2, 5 s) instead of
looping, but updates are delayed. A denial of service, not a leak.

Lost phone: S is compromised, delete the chain on the Mac and create a new one. Encryption does not protect against an
unlocked device: `user://chaine.cfg` is in the app's private storage, like `config.json` on the Mac.
