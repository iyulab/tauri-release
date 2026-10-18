// The updater stage for apps that update through tauri-plugin-updater: write latest.json for a signed
// installer, and check an installer, its updater signature and latest.json the way the installed app
// will before it installs them.
//
//   node updater.mjs manifest --installer <file> --sig <file.sig> --version <v> --url <url> [--notes <text>] --out <latest.json>
//   node updater.mjs verify   --installer <file> --sig <file.sig> --manifest <latest.json> --pubkey <base64> --version <v> --url <url>
//
// The key and the signature are minisign's, as Tauri writes them: each is base64 of a text whose second
// line is base64 of the binary form — key: "Ed" · key id (8) · Ed25519 key (32); signature: algorithm (2)
// · key id (8) · signature (64). Algorithm `ED` signs the BLAKE2b-512 hash of the file, `Ed` the file
// itself. The third and fourth lines are the trusted comment and a signature over signature ‖ comment.
// The updater rejects a signature whose trusted comment names another version than latest.json's.
import { createHash, createPublicKey, verify } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'
import { basename } from 'node:path'
import { pathToFileURL } from 'node:url'

const ED25519_SPKI = Buffer.from('302a300506032b6570032100', 'hex')

/** The lines of a base64-wrapped minisign text, and the binary form on its second line. */
export function unwrap(wrapped) {
  const lines = Buffer.from(wrapped.trim(), 'base64').toString('utf8').split('\n').map((l) => l.replace(/\r$/, ''))
  if (lines.length < 2 || !lines[1]) throw new Error('not a minisign key or signature')
  return { lines, bytes: Buffer.from(lines[1].trim(), 'base64') }
}

/** The name GitHub gives an uploaded asset: it turns spaces into dots. */
export function assetName(file) {
  return basename(file).replaceAll(' ', '.')
}

/**
 * Why `file` and `signature` do not verify against `pubkey` for `version` — or null when they do.
 */
export function signatureProblem(file, signature, pubkey, version) {
  const key = unwrap(pubkey).bytes
  const { bytes: sig, lines } = unwrap(signature)
  if (key.length !== 42 || key.subarray(0, 2).toString('latin1') !== 'Ed') return 'the public key is not a minisign Ed25519 key'
  if (sig.length !== 74) return 'the signature is not a minisign signature'
  if (!key.subarray(2, 10).equals(sig.subarray(2, 10))) return 'the signature was made with another key'
  const algorithm = sig.subarray(0, 2).toString('latin1')
  if (algorithm !== 'ED' && algorithm !== 'Ed') return `unknown signature algorithm '${algorithm}'`
  const publicKey = createPublicKey({ key: Buffer.concat([ED25519_SPKI, key.subarray(10)]), format: 'der', type: 'spki' })
  const message = algorithm === 'ED' ? createHash('blake2b512').update(file).digest() : file
  if (!verify(null, message, publicKey, sig.subarray(10))) return 'the signature does not match the installer (it was made over other bytes)'
  const at = lines.findIndex((l) => l.startsWith('trusted comment: '))
  if (at < 0 || !lines[at + 1]) return 'the signature has no trusted comment'
  const comment = lines[at].slice('trusted comment: '.length)
  if (!verify(null, Buffer.concat([sig.subarray(10), Buffer.from(comment, 'utf8')]), publicKey, Buffer.from(lines[at + 1].trim(), 'base64'))) {
    return 'the trusted comment is not signed by the key'
  }
  const signed = comment.split('\t').find((f) => f.startsWith('version:'))?.slice('version:'.length)
  if (signed !== version) return `the signature is bound to version '${signed ?? '(none)'}', not '${version}'`
  return null
}

/** Why `manifest` does not describe this installer and signature — or null when it does. */
export function manifestProblem(manifest, signature, version, url) {
  if (manifest.version !== version) return `latest.json says version '${manifest.version}', not '${version}'`
  const windows = manifest.platforms?.['windows-x86_64']
  if (!windows) return 'latest.json has no windows-x86_64 entry'
  if (windows.signature !== signature.trim()) return 'latest.json carries another signature than the .sig file'
  if (windows.url !== url) return `latest.json points at ${windows.url}, not ${url}`
  if (Number.isNaN(Date.parse(manifest.pub_date))) return 'latest.json has no valid pub_date'
  return null
}

function args(argv) {
  const out = {}
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--') || argv[i + 1] === undefined) throw new Error(`expected --name value, got '${argv[i]}'`)
    out[argv[i].slice(2)] = argv[i + 1]
  }
  return out
}

function need(a, ...names) {
  for (const n of names) if (!a[n]) throw new Error(`--${n} is required`)
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [command, ...rest] = process.argv.slice(2)
  const a = args(rest)
  if (command === 'manifest') {
    need(a, 'installer', 'sig', 'version', 'url', 'out')
    const manifest = {
      version: a.version,
      ...(a.notes ? { notes: a.notes } : {}),
      pub_date: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
      platforms: { 'windows-x86_64': { signature: readFileSync(a.sig, 'utf8').trim(), url: a.url } },
    }
    writeFileSync(a.out, JSON.stringify(manifest, null, 2) + '\n')
    console.log(`${a.out}: version ${a.version} → ${a.url}`)
  } else if (command === 'verify') {
    need(a, 'installer', 'sig', 'manifest', 'pubkey', 'version', 'url')
    const signature = readFileSync(a.sig, 'utf8')
    const problem =
      signatureProblem(readFileSync(a.installer), signature, a.pubkey, a.version) ??
      manifestProblem(JSON.parse(readFileSync(a.manifest, 'utf8')), signature, a.version, a.url)
    if (problem) {
      console.error(`${basename(a.installer)}: ${problem}`)
      process.exit(1)
    }
    console.log(`${basename(a.installer)}: the updater signature verifies for ${a.version}, and latest.json points at it`)
  } else {
    console.error('usage: node updater.mjs manifest|verify --name value …')
    process.exit(2)
  }
}
