# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Repository, scope and license.
- `docs/design.md`: the design of the first workflow — signing only in code-sign's reusable workflow, the
  uninstaller signed between two bundling passes (measured), the stages and the inputs.
- `.github/workflows/windows.yml`: the Windows release as a reusable workflow — sign the built files,
  bundle, sign the uninstaller and NSIS plugins, bundle again with them, sign the installer, check the
  installed copy, and optionally draft a release.
- `actions/bundle` (bundle without re-patching; collect or substitute what only the bundle produces) and
  `actions/verify` (install and check every installed file's signature).
- `self-test.yml`: both actions end to end on `tests/fixture` with a certificate made for the test.
- The updater stage, for apps that update through tauri-plugin-updater (`updater: true`): `updater-sign`
  makes the updater signature over the signed installer, bound to the version, and writes `latest.json`
  pointing at the installer asset of the release — the updater key reaches that job only, as an explicit
  secret; `verify-updater` checks both with the public key the app carries, as the installed app will;
  the draft carries them and is checked to hold the asset `latest.json` points at. `actions/updater`
  (sign or verify — the check needs nothing installed). The bundling passes no longer make updater
  artifacts whatever the caller's overlays say: there is no key there, and the installer is signed later.
- `updater-environment`: the caller's environment holding the updater key, for a key kept as an
  environment secret — passed by name, such a secret resolves only in a job that names its environment,
  and was otherwise empty.

### Fixed

- With `updater` and `draft` together, the cleanup no longer removes the updater signature and `latest.json` before
  the draft takes them: it waits for the draft (the draft failed with the artifact not found).
- The draft's tag is made on the commit the run built (`--target`), not on the default branch's head at
  the time it is published.
