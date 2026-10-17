# tauri-release

Reusable GitHub Actions for releasing a Tauri desktop app on Windows — the steps every such app
writes into its own `release.yml`, kept in one place.

A release of a Tauri app with a bundled helper (for example a .NET sidecar) goes through the same
stages whatever the app is:

1. build the app and its helpers without bundling, in a job that holds no secrets
2. sign the executables that will be bundled — only a fixed list, by the signing job of
   [code-sign](https://github.com/iyulab/code-sign)
3. bundle the installer from the signed files, so the bundler does not re-sign or patch them
4. sign the installer
5. check what was produced: the Authenticode signature of every executable inside the installed
   copy, the updater signature, the update manifest
6. write the update manifest (`latest.json`) and a draft release

This repository will hold that sequence as a `workflow_call` workflow plus the small composite
actions it is made of. Signing itself stays in code-sign; this repository only calls it.

**Status:** no workflow is published yet. See [SCOPE.md](SCOPE.md) for what belongs here, and [docs/design.md](docs/design.md) for the shape of the first workflow.

## License

MIT — see [LICENSE](LICENSE).
