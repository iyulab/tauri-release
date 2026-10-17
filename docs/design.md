# Design — the first workflow

Status: draft. Nothing here is published as a workflow yet; this is the shape the first one is built to.

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
sign-uninstaller code-sign       sign.yml on the one uninstaller
bundle-2         no credential   bundle again; the sign hook puts the signed uninstaller in
sign-installer   code-sign       sign.yml on the one installer
verify           no credential   install the installer into a temporary folder and check every
                                 installed executable's Authenticode signature, the
                                 uninstaller's included; check the updater signature
draft            contents: write updater signature over the signed installer, latest.json, a draft
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
2. **sign-uninstaller** signs that copy with code-sign.
3. **bundle-2** runs the bundler again from the same inputs, with a hook that replaces the
   uninstaller it is given by the signed copy.

**Measured** (`measure-two-pass.yml` on `tests/fixture`, Tauri CLI 2.12.1, `windows-latest`): the
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
| Updater | on or off; the updater key secrets; where `latest.json` points |
| Variants | an offline installer that carries the WebView2 runtime, on or off |
| Verification | the installed files that must be signed (default: every `.exe` and `.dll`) |
| Release | tag, title, notes file, asset names and a version-free alias |

## Not here

- Signing itself, the credential and its pinned tools — code-sign.
- Publishing the draft — a person's act.
- A caller's own checks (talking to its diagnostics collector, end-to-end tests of its app) — the
  caller's steps before or after this workflow.
