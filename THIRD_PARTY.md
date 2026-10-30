# Third-party software and assets

AImpire is built on the work below. Thank you to every author.

## Software

| Component | Used for | License |
|---|---|---|
| [Godot Engine](https://godotengine.org) 4.7 | the game, on macOS and Android; the engine is embedded in every build | MIT. Godot also embeds third-party libraries (FreeType, mbedTLS, zstd and others) under their own permissive licenses, listed in [its COPYRIGHT.txt](https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt) |
| [Bun](https://bun.sh) | compiles the local server into a single binary embedded in the macOS app | MIT. Bun embeds JavaScriptCore (LGPL-2.1) and other libraries listed in [its license page](https://bun.sh/docs/project/licensing) |
| [Node.js](https://nodejs.org) 22 | runs the local server during development and the relay | MIT |

The local server and the relay have no npm dependencies.

## 3D models

- **Fantasy Town Kit** (2.0) and **Mini Characters** (1.0) by [Kenney](https://kenney.nl), CC0 1.0.
  License files: `godot/assets/town/License-Kenney.txt`, `godot/assets/people/License-Kenney.txt`.
- **Stylized Nature MegaKit** (free version) by [Quaternius](https://quaternius.com), CC0 1.0.
  License file: `godot/assets/nature/License_Standard.txt`.

## Sound and music

- **Impact Sounds** (1.0) by [Kenney](https://kenney.nl/assets/impact-sounds), CC0 1.0.
  License file: `godot/assets/sfx/License-Kenney.txt`.
- **"Birds and Wind - Ambient"** by Spring Spring,
  [OpenGameArt](https://opengameart.org/content/birds-and-wind-ambient-birds-wind-and-synth), CC0 1.0.
- **"Shakkar"** by zesona, [OpenGameArt](https://opengameart.org/content/shakkar), CC0 1.0.

CC0 asks for no credit; it is given here anyway.

## Fonts

All under the [SIL Open Font License 1.1](https://openfontlicense.org), license texts in `godot/assets/fonts/`:

- **Bricolage Grotesque**, Copyright 2022 The Bricolage Grotesque Project Authors
- **Figtree**, Copyright 2022 The Figtree Project Authors
- **Cinzel**, Copyright 2020 The Cinzel Project Authors

## Data

- **BIP 39 English wordlist** (2048 words), from the
  [Bitcoin BIPs repository](https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt), used to show the sync
  secret as 12 words. Copied unchanged; SHA-256 of the file:
  `2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda`.

## Services you may choose to use

- **ElevenLabs**: only with your own key, for the villager voices you generate yourself (`ASSETS.md`) and the optional
  detailed voices (`PRIVACY.md`). Not affiliated with AImpire.
