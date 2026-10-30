# Contributing

AImpire is a small personal project shared as is. Issues and pull requests are welcome; answers may take a few days.

- **Security issues**: never in a public issue, see `SECURITY.md`.
- **Before a pull request**: open an issue for anything larger than a fix, so we agree on the idea first.
- **Principles that do not move**: the app only reads the session logs and never writes to them, never sends a request
  to a model or spends tokens, sends nothing anywhere unless a sync chain is created (and then only encrypted), and
  needs no account. A change that breaks one of these will not be merged.
- **Text**: interface and documentation in English. No long or en dashes (the CI refuses them).
- **Assets**: only files you may redistribute, with their license next to them and a line in `ASSETS.md` and
  `THIRD_PARTY.md`.
- **Checks** (all run by the CI):

  ```bash
  node tools/check-repo.mjs
  cd daemon && node --test
  cd relay && node --test
  godot --headless --path godot -s tests/test_sync_crypto.gd   # and the other godot/tests/test_*.gd
  ```

By contributing you agree that your contribution is licensed like the files you change: MIT for everything except
`relay/`, which is AGPL-3.0-only.
