---
name: install-aimpire
description: Installs AImpire (your Claude Code sessions as a Greco-Roman city) on an Apple Silicon Mac from a GitHub release, checking the requirements, the checksum, the Gatekeeper quarantine and the first launch. Invoke with /install-aimpire.
---

# Install AImpire

Rules: never use `sudo`, change nothing outside `/Applications/AImpire.app` and `~/Library/Application Support/AImpire/`,
never read or print the content of `~/.claude/projects` (these are the person's conversations). Ask before every step
that changes the machine.

1. **Platform**: `uname -sm` must print `Darwin arm64`. Otherwise, explain that there is no package for this machine yet
   and that AImpire can be built from source (README, "Build from source").
2. **Claude Code**: `ls ~/.claude/projects | head` should list folders. Otherwise, explain that AImpire has nothing to
   show until Claude Code has been used at least once.
3. **Download**: give the file names, the source and the sizes
   (`gh release view --repo sidalidev/aimpire --json tagName,assets`), then, in a new empty folder:
   `D=$(mktemp -d) && gh release download --repo sidalidev/aimpire --pattern 'AImpire-*-macos.zip*' --dir "$D"`.
   Without `gh`, download `AImpire-<version>-macos.zip` and `AImpire-<version>-macos.zip.sha256` from
   https://github.com/sidalidev/aimpire/releases/latest into that folder.
4. **Verify**: `cd "$D" && shasum -a 256 -c AImpire-*-macos.zip.sha256` must print `OK`. Stop if it does not.
5. **Install**: `ditto -x -k "$D"/AImpire-*-macos.zip "$D/out" && rm -rf /Applications/AImpire.app && ditto "$D/out/AImpire.app" /Applications/AImpire.app`.
   The app is not notarized: `xattr -dr com.apple.quarantine /Applications/AImpire.app` (explain why: ad hoc
   signature, no Apple Developer ID).
6. **First launch**: `open -a AImpire`, then wait for `curl -s 127.0.0.1:7777/health` and show `scanning.done/total`.
   Warn that the first scan can take a few minutes depending on the amount of logs.
7. **Voices** (optional, default no): villager voices are generated with the person's own ElevenLabs key when building
   from source (`tools/gen-voices.mjs`). "Detailed voices" send the start of a session message to ElevenLabs: only if
   the person wants it, explain that it needs their own key in `~/Library/Application Support/AImpire/.env`
   (`ELEVENLABS_API_KEY=...` and `AIMPIRE_VOIX=1`). Never read or print the key.
8. **Keys**: Tab cockpit, R daily summary, W weekly report, J journal, H discreet mode, P picture in picture, M music,
   Esc settings.
9. **Uninstall**: quit the app, `rm -rf /Applications/AImpire.app`, and only if the person wants to erase their progress,
   `rm -rf ~/Library/Application\ Support/AImpire` (or Settings, About AImpire, Erase everything).
