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
