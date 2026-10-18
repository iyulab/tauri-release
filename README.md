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

`.github/workflows/windows.yml` is that sequence as a `workflow_call` workflow, from step 2 on: the
caller builds (step 1, its own) and hands over the files to sign and what bundling reads. The
uninstaller and the NSIS plugins, which the bundler produces itself, are signed between two bundling
passes, so the signing credential never enters a job that runs the app's toolchain. The workflow is
made of two composite actions that can be used on their own:

- `actions/bundle` — bundle from built, signed files without re-patching them; `collect` the files
  only the bundle produces, or `substitute` their signed copies.
- `actions/verify` — install the installer silently and check the signature of every installed
  executable and DLL, the uninstaller included; then uninstall.

`.github/workflows/self-test.yml` runs both on a Tauri app with nothing in it, with a certificate
made for the test standing in for code-sign. Signing itself stays in code-sign; this repository only
calls it.

For an app that updates through Tauri's updater (`updater: true`), the workflow also makes the
updater signature over the signed installer and writes `latest.json`; the updater key reaches that
job only. A variant of the installer — one that carries the WebView2 installer, say — is a second
call with its `--config` overlay and its own `installer-artifact`, after the first: the calls share
the names of their intermediate artifacts. A calling job grants what the jobs inside ask for —
`id-token: write` for the signing jobs and `contents: write` for the draft job, even with `draft: false`: a run
whose called jobs ask for more than the caller grants does not start.

**Status:** unreleased. See [SCOPE.md](SCOPE.md) for what belongs here, and
[docs/design.md](docs/design.md) for the design.

## License

MIT — see [LICENSE](LICENSE).
