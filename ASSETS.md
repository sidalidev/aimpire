# Assets

Every file the game ships that is not code, where it comes from and under which license. Full credits and license
texts: `THIRD_PARTY.md`.

| Folder | Content | Source | License |
|---|---|---|---|
| `godot/assets/town/` | buildings, walls, banners, props (`.glb`) and their palette | Kenney, Fantasy Town Kit 2.0 | CC0 1.0 |
| `godot/assets/people/` | villagers (`character-*.glb`) and their palette | Kenney, Mini Characters 1.0 | CC0 1.0 |
| `godot/assets/nature/` | trees, bushes, rocks, grass, flowers (`.gltf`, `.bin`, textures) | Quaternius, Stylized Nature MegaKit (free version) | CC0 1.0 |
| `godot/assets/sfx/` | impacts, bell, horn, fanfare, click | Kenney, Impact Sounds 1.0 | CC0 1.0 |
| `godot/assets/sfx/oiseaux.ogg` | birds and wind ambience | "Birds and Wind - Ambient" by Spring Spring, OpenGameArt | CC0 1.0 |
| `godot/assets/music/ambiance.ogg` | ancient city loop | "Shakkar" by zesona, OpenGameArt | CC0 1.0 |
| `godot/assets/fonts/` | Bricolage Grotesque, Figtree (interface), Cinzel (names in the world) | their project authors | SIL Open Font License 1.1 |
| `godot/assets/bip39-english.txt`, `daemon/bip39-english.js` | BIP 39 English wordlist (2048 words) | Bitcoin BIPs repository | see `THIRD_PARTY.md` |
| `godot/assets/ui/icons/`, `godot/assets/ui/curseur*.png` | resource icons and mouse cursors | made for AImpire | MIT, like the code |
| `icon/temple.svg`, `godot/icon.png`, `godot/build/` icons | app icon and its exports (`tools/gen-icons.sh`) | made for AImpire | MIT, like the code |
| `docs/screenshots/`, `docs/captures/` | screenshots of the app with invented demo data | made for AImpire | MIT, like the code |

The license files shipped by the authors stay next to their assets: `License-Kenney.txt`, `License_Standard.txt`,
`OFL-*.txt`, and a `CREDITS.md` in `music/` and `sfx/`.

## Villager voices

The spoken lines of the villagers ("To work!", "Done.", ...) are **not in this repository**. They are synthesized with
ElevenLabs, whose terms govern the generated audio, so each person generates their own with their own account:

```bash
ELEVENLABS_API_KEY=your-key node tools/gen-voices.mjs
```

The files are written to `godot/assets/voix/` (ignored by git); after `godot --headless --path godot --import` they are
packed into the next build. Without them the game works the same, the villagers only show their speech bubble; music
and sound effects are unchanged. Your use of the generated files
is between you and ElevenLabs.

## Adding an asset

Only assets you may redistribute: CC0, CC-BY (with the credit added to `THIRD_PARTY.md`), OFL for fonts, or your own
work under the project license. Put the author's license file next to the asset and add a row above.
