# Scope

tauri-release holds the release pipeline of a Tauri desktop app on Windows, and on macOS (designed in
[docs/design.md](docs/design.md), not built yet): the GitHub Actions steps from source to a draft release. This document draws the line around that job.

## What it owns

- **The order of the stages** — build without secrets, sign a fixed list of executables, bundle
  from the signed files, sign the installer, verify, publish a draft. Getting this order wrong is
  how a signing credential ends up in a job that runs third-party build code, or how a bundler
  silently replaces a signed executable with an unsigned copy.
- **Verification of what was produced** — the Authenticode signature of each executable, checked
  in the files the installer actually installs; the updater signature; the update manifest.
- **The update manifest** — `latest.json` for the Tauri updater, built from the produced files.
- **Variants of the installer** a Tauri app commonly ships, such as one that carries the WebView2
  runtime for machines without network access.

## What it does not do

- **Sign.** The signing job, its credential and its pinned tools are
  [code-sign](https://github.com/iyulab/code-sign)'s. This repository calls it and passes the list
  of files; it never holds the credential.
- **Know its callers.** Product names, file names of a caller's helpers, environment variable
  names and wording arrive as inputs. No workflow, default, comment or test names a consuming app.
- **Build the app's own code.** How a caller builds its helpers (a .NET publish, a Node bundle) is
  the caller's step; this repository runs it where the stage order says.
- **Publish.** It produces a draft release. Making it public is a person's act.
- **Check how the installed app behaves.** Verification here asks one question of what the
  pipeline produced — is every file it installs signed as required — and asks it between signing
  and the draft. Whether the installed app starts, installs over a published version, runs on a
  clean machine and uninstalls cleanly is the app's own check, written with
  [tauri-kit-dev](https://github.com/iyulab/tauri-kit-dev)'s `installer` tools. Both install
  silently into a temporary folder to look; that step is a pair of installer flags, not a shared
  component, so neither calls the other.
- **Desktop frameworks other than Tauri.** Apps built on other shells call code-sign directly.

## Admission

A step belongs here when it is written the same way for an unrelated Tauri app on the same platform and can
be stated without naming a caller — every constant it needs becomes an input.
