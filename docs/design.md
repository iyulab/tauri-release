# Design — the first workflow

Status: Windows built — `.github/workflows/windows.yml` with `actions/bundle`, `actions/verify` and `actions/updater` (the updater stage, for apps on tauri-plugin-updater); unreleased. macOS: the packaging and check actions built, the workflow designed (below).

## The problem

A Tauri app on Windows that ships signed installers repeats the same release sequence in its own
`release.yml`. The copies differ in one decision that matters for security: **where the signing
credential lives.**

- **Signing inside the bundler** (`bundle.windows.signCommand` calling a sign command, prepared by
  code-sign's action earlier in the same job): every file the bundler produces is signed, the NSIS
  uninstaller included. But the job that holds the credential also runs the toolchain, the package
  manager, the build scripts and every action they pull in — any of them can sign arbitrary files.
- **Signing a fixed list in a job of its own** (code-sign's reusable `sign.yml`): the job that
  holds the credential runs nothing of the app. The build and the bundle run without it. But the
  uninstaller is produced *inside* the bundle step, after the list was signed, so it ships unsigned.

The first workflow takes the second as its only mode, and closes its gap.

## Stages and where the credential is

```
build            no credential   build the app and its helpers (--no-bundle); hand out
                                 exactly the files to sign, and what bundling reads
sign-binaries    code-sign       sign.yml on the fixed list
bundle-1         no credential   bundle from the signed files (--no-binary-patching);
                                 the sign hook only copies the uninstaller out
sign-extras      code-sign       sign.yml on the uninstaller and the NSIS plugins
bundle-2         no credential   bundle again; the sign hook puts the signed uninstaller in
sign-installer   code-sign       sign.yml on the one installer
verify           no credential   install the installer into a temporary folder and check every
                                 installed executable's Authenticode signature, the
                                 uninstaller's included
updater-sign     updater key     (updater: true) the updater signature over the signed installer,
                                 bound to the version, and latest.json — no other permission
verify-updater   no credential   (updater: true) the signature checked with the public key the
                                 app carries, latest.json's version, signature and URL
draft            contents: write a draft carrying the installer (and the .sig and latest.json),
                                 checked to hold the asset latest.json points at
```

- `--no-binary-patching` is required whenever executables are signed before bundling: patching
  rewrites the app executable and breaks its signature.
- A sign hook that does not sign is still a hook: `makensis` runs it for the uninstaller and ignores
  its exit code. That is why the uninstaller is *checked on the installed copy*, never assumed.

### The uninstaller in two passes (to be measured)

`makensis` builds the uninstaller while it compiles the installer, runs the sign command on it
(`!uninstfinalize`), and then embeds that file. The plan:

1. **bundle-1** runs the bundler with a hook that copies the uninstaller it is given out of the
   build (and leaves every other file alone). Its installer is thrown away.
2. **sign-extras** signs that copy, and the NSIS plugins, with code-sign.
3. **bundle-2** runs the bundler again from the same inputs, with a hook that replaces the
   uninstaller it is given by the signed copy.

**Measured** (a one-off workflow, since folded into `self-test.yml`, on `tests/fixture`, Tauri CLI 2.12.1, `windows-latest`): the
installed `uninstall.exe` is byte for byte the copy signed between the passes, its signer is the
certificate that signed it, the installed app executable is the one that was built, and the signed
uninstaller removes the app. The swap holds.

What the hook is given, in order, in each pass (from its log):

| File | Given by | In split signing |
|---|---|---|
| the app executable (`target/release/<app>.exe`) | the bundler | already signed by `sign-binaries` — the hook must leave it alone |
| NSIS plugins (`target/release/nsis/x64/Plugins/x86-unicode/*.dll`, five) | the bundler | unsigned today; collect them with the uninstaller and sign them in the same pass |
| the uninstaller — a temporary file (`nst*.tmp`) | `makensis` (through `cmd.exe`) | collect in pass 1, substitute in pass 2 |
| the installer (`bundle/nsis/*-setup.exe`) | the bundler | left alone; `sign-installer` signs it |

So the hook tells the uninstaller by who calls it (`makensis` among its parents), not by its name,
and treats the plugins by their place under `nsis/`. If a later bundler stops calling the hook for a
file, the installed-copy check fails rather than shipping it unsigned.

## Inputs

Everything a caller differs in arrives as an input; nothing defaults to a caller's names.

| Area | Inputs |
|---|---|
| Source | repository and ref to build, token for a private source, submodules, working directory of the app |
| Toolchain | Node version, package manager, .NET version or `global.json`, Tauri CLI version |
| Before bundling | a command that builds the helpers and anything else the bundle reads (a .NET publish, notices, tests) — run in the build job |
| Build-time values | names of secrets the build reads (a diagnostics connection, say), passed through as environment |
| Signing | the fixed list of files to sign, relative to the app; signature description and URL |
| Bundle | extra `--config` overlays; bundles (`nsis`); target |
| Updater | `updater` on or off; `version`; `updater-pubkey`; the key as the secrets `updater-key` and `updater-key-password` (explicit, not `secrets: inherit` — only `updater-sign` sees them); `updater-environment` when the key is an environment secret (it resolves only in a job of that environment); `latest.json` points at the installer asset of the release tagged `tag` |
| Variants | a second call with the variant's `--config` overlay and its own `installer-artifact`, after the first (the intermediate artifacts share names) — the caller adds that installer to the draft |
| Verification | the installed files that must be signed (default: every `.exe` and `.dll`) |
| Release | tag, title, notes file, asset names and a version-free alias |

## macOS

Status: `actions/macos-image` (staple, disk image, update archive) and `actions/macos-verify` built and
self-tested on an ad hoc bundle; the workflow and its signing stages not yet. The same rule as on Windows: the job that holds a signing credential
runs nothing of the app.

### Stages and where the credential is

```
build            no credential   the caller's: build the app and its helpers, and the bundle
                                 (`--bundles app`) signed ad hoc (`signingIdentity` `-` — a bundle
                                 left unsigned has no sealed resources and fails every check);
                                 hand it out as a tar archive (an uploaded folder loses the
                                 symbolic links and modes a bundle's frameworks need)
sign-bundle      macOS signing   re-sign every Mach-O file inside the bundle, deepest first, with
                                 the hardened runtime, a timestamp and the entitlements the caller
                                 names per file (a helper that compiles code at run time needs
                                 `allow-jit`); then the bundle itself, which seals what is inside
notarize-bundle  notary key      submit the signed bundle and wait for the verdict
package          no credential   staple the bundle; make the compressed disk image (the bundle and
                                 a link to Applications, with `hdiutil` — no Finder automation);
                                 make the update archive (`<app>.app.tar.gz`) from the stapled bundle
sign-image       macOS signing   sign the disk image
notarize-image   notary key      submit the disk image and wait
verify           no credential   staple the disk image; then check the stapled copies: the bundle's
                                 signature, strictly and with nested code; Gatekeeper's assessment
                                 of the bundle and of the image; each stapled ticket; that the
                                 signing team is the one the caller names; that the bundle inside
                                 the mounted image is the one in the update archive
updater-sign     updater key     (updater: true) as on Windows, over the update archive
draft            contents: write as on Windows
```

- **Signing after bundling is safe here.** Windows needs `--no-binary-patching` and two bundling
  passes because the bundler rewrites and produces executables; on macOS the bundle's seal is
  computed when the bundle itself is signed, so re-signing every file inside and then the bundle
  replaces the ad hoc signatures completely. The bundler is never given the credential.
- **The bundler's own signing is not used.** It signs the main executable and frameworks but not
  every helper a bundle may carry (a native server, its libraries, a self-contained runtime), and it
  would need the credential in the job that runs the toolchain.
- **Stapling needs no credential**, so it runs in the no-credential jobs. A stapled ticket lets the
  app's own update check confirm notarization with no network.
- **Without the signing inputs** the signing and notarizing stages are skipped: the bundle stays ad
  hoc, `verify` checks only that the ad hoc signature holds, and the draft says the build is not for
  distribution. This is how the pipeline is exercised before a Developer ID exists.
- **Runner**: GitHub-hosted `macos-latest` (Apple silicon). macOS minutes cost ten times Linux minutes
  in a private repository, so the macOS jobs stay few: the stages above that need no macOS tool
  (`draft`) run on Linux.

### What the macOS signing stages need

The signing credential (a Developer ID Application certificate) and the notary key (an App Store
Connect API key) belong to the organization, like the Windows certificate: they are code-sign's to
hold, behind a reusable workflow that signs and notarizes what it is handed and runs nothing else.
code-sign has no such layer yet; it is requested once the certificate exists. Until then the inputs
are empty and the stages are skipped.

### Inputs (in addition to the shared ones)

| Area | Inputs |
|---|---|
| Bundle | the bundle archive artifact; entitlements per file inside the bundle (paths relative to the bundle) |
| Signing | the team ID the signature must name; nothing else — the identity and keys are the signing layer's |
| Image | volume name; image file name and a version-free alias |
| Updater | as on Windows; the manifest's platform key (`darwin-aarch64`). An app released on both platforms passes the Windows call's `latest.json` in, and the macOS call adds its platform to it |

### Open

- Whether the update archive is notarized as its own submission or carries the bundle's stapled
  ticket only (the bundle inside is what runs, and it is stapled) — measured on the first signed run.
- Universal (Intel and Apple silicon) bundles: not planned; arm64 only until a caller needs Intel.

## Not here

- Signing itself, the credential and its pinned tools — code-sign.
- Publishing the draft — a person's act.
- A caller's own checks (talking to its diagnostics collector, end-to-end tests of its app) — the
  caller's steps before or after this workflow.
