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

What must hold, and will be measured before the workflow is published: the uninstaller of pass 1
works in place of pass 2's (same script, same inputs); the embedded file is the signed copy (its
signature is Valid on the installed copy); nothing else in the installer changes because of the
swap. If it does not hold, the fallback is to ship an unsigned uninstaller and say so, as callers
using split signing do today — never to bring the credential into a bundle job.

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
