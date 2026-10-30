# Threat model

**Protected**: what your sessions say (titles, requests, replies, project names and paths). They never leave the Mac in
clear. The sync chain encrypts the published state end to end (AES-256-CBC with HMAC-SHA256, keys derived from a
128-bit secret that only the Mac and your paired phones know, `docs/SYNC.md`).

**Against whom**: the relay and its host, anyone on the network between your devices and the relay, a phone that is
not paired, and screen sharing (discreet mode removes names, paths and titles before display and before encryption).

**Not protected**:
- The relay sees a random chain id, message sizes, times and your IP address while connected. Traefik on the server may
  log IP addresses. Sizes are padded to 16 KiB steps, not hidden.
- Anyone who reads the 12 words, the link or the QR code gets the Empire. They are hidden by default on the Mac.
- On the Mac, the chain secret is stored in `config.json` (mode 0600), not in the Keychain. On Android, in the app's
  private storage, not in the Keystore. Malware running as you can read both.
- Session logs in `~/.claude` are readable by any program running as you. AImpire only reads them.
- Detailed voices, when you turn them on, send short sentences to ElevenLabs.
- Updates: the SHA-256 is checked against the manifest served by the same host, which is not signed. A compromised
  server could serve a matching file. On Android, the OS refuses an update signed by another certificate. The Mac app is
  signed ad hoc, so macOS gives no such guarantee.

**Post-quantum**: symmetric cryptography only (AES-256, HMAC-SHA256, 128-bit secret), no key exchange to break.

**Cyber Resilience Act**: free, non-commercial and not distributed on a market; outside its scope for now.
