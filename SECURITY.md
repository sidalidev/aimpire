# Security

## Report a vulnerability

Please report privately, never in a public issue:

- on GitHub: the repository's Security tab, "Report a vulnerability" (private advisory), or
- by email to **contact@sidali.dev** with "AImpire security" in the subject.

You get a first answer within 72 working hours, and a fix or a written assessment within 14 days.

## Signing certificate

Android APK, signer certificate `CN=AImpire, O=Sid Ali, C=FR`, SHA-256:

```
79:E3:7E:06:72:10:2C:6B:EC:29:B0:E8:B5:5E:58:C0:51:62:98:C7:17:BE:6E:9E:77:18:DC:50:63:6E:9E:A0
```

Check a downloaded APK with `apksigner verify --print-certs aimpire-<version>.apk`. On the phone, Settings, About
AImpire shows the first 8 and last 4 characters of the fingerprint, read from the installed APK.

macOS: the app is signed ad hoc (no Apple Developer ID yet), so there is no certificate to compare. Check the SHA-256 of
the zip against the `.sha256` file of the GitHub release, or against `https://aimpire.sidali.dev/update.json`.

## Scope

In scope: the game (`godot/`), the local server (`daemon/`), the relay (`relay/`, and the default instance
`aimpire.sidali.dev`), the sync chain cryptography (`docs/SYNC.md`), the update check and the release scripts
(`tools/`).

Out of scope: bugs in Godot, Node or Bun themselves (report them upstream), ElevenLabs, and a Mac or phone that is
already compromised.

## Reviews

- Latest: `docs/security/2026-10-24.md`, internal review by the developer. No third-party audit.
- Threat model: `docs/THREAT_MODEL.md`.
- A review is redone at least every 6 months and at every change of cryptography, network or permissions. The CI fails
  when the latest review is older than 6 months.
