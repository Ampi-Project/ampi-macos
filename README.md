# Ampi for macOS

A free native music player with an original retro interface, whole-interface themes, and planned Winamp Classic and Modern skin import.

## Current state

Documentation bootstrap only. This repository has its own Git history boundary, GPLv3 license file, and [development checklist](DEVELOPMENT.md). There is no Xcode project, Swift package, application, importer, or build command yet. The GitHub repository is connected; no application release has been created.

## Repository

[Ampi-Project/ampi-macos on GitHub](https://github.com/Ampi-Project/ampi-macos) is the `origin` remote. The local `main` branch tracks `origin/main` and builds on the existing GitHub initial commit.

To push local commits from this repository:

```sh
git push origin main
```

GitHub authentication must use an account with write access to the organization repository. Git author information identifies commit authors; it does not authenticate a push.

## Proposed stack and responsibilities

Swift with AppKit for the native application. This project owns its playback integration, queue/library state, skin renderer, legacy adapters, persistence, macOS permissions, media controls, and packaging. Select audio and rendering dependencies after a feasibility prototype.

Implement a versioned Ampi theme contract independently. Building or running this player must not require the Windows, Linux, or theme authoring repositories. Pin published specification artifacts when they exist.

## Development order

Contract and cleared fixtures → native drawing/input prototype → local playback → Classic skins and equalizer → native theme switching → platform parity → library → Modern XML/MAKI compatibility → release preparation.

The local workspace has an [unversioned overall plan](../ampi-flow/README.md). That link is optional coordination context and is not available in a standalone clone. Keep this repository's instructions self-contained as implementation begins.

## License

Original repository content is licensed under GPL-3.0-only; see [LICENSE](LICENSE). Official Ampi downloads will be free. Independently authored themes retain their own licenses; GPL redistribution requirements still apply to copied GPL material. Winamp skin support is a compatibility goal, not a claim of affiliation.
