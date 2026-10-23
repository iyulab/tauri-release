#!/usr/bin/env bash
# Checks what a macOS release carries: the bundle inside the disk image is the one in the update
# archive, file for file; its signature holds, strictly and with nested code. With a team ID it must
# also be a notarized Developer ID signature of that team — the bundle and the image each stapled,
# each accepted by Gatekeeper. Without one the build is ad hoc: the signature is checked to hold and
# the run is told the build is not for distribution.
#
#   verify.sh --image <path.dmg> --archive <path.app.tar.gz> [--team <team ID>]
set -euo pipefail

image='' archive='' team=''
while [ $# -gt 0 ]; do
  case "$1" in
    --image) image=$2 ;;
    --archive) archive=$2 ;;
    --team) team=$2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift 2
done
[ -f "$image" ] && [ -f "$archive" ] || { echo '--image and --archive must name files' >&2; exit 2; }
if [ -n "$team" ] && ! [[ "$team" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "not a team ID: '$team'" >&2; exit 2
fi
fail() { echo "::error::$*" >&2; exit 1; }

work=$(mktemp -d)
mount="$work/image"
cleanup() {
  hdiutil detach -quiet "$mount" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
mkdir "$mount" "$work/archive"
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mount" "$image"
tar -xzf "$archive" -C "$work/archive"

one_bundle() {
  local found=("$1"/*.app)
  [ ${#found[@]} -eq 1 ] && [ -d "${found[0]}" ] || fail "expected one bundle in $2, found ${#found[@]}"
  echo "${found[0]}"
}
app=$(one_bundle "$mount" 'the image')
unpacked=$(one_bundle "$work/archive" 'the archive')
[ "$(basename "$app")" = "$(basename "$unpacked")" ] || fail "the image holds $(basename "$app"), the archive $(basename "$unpacked")"

# Every entry: its kind, mode, and content or link target.
tree() {
  (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then echo "link $p -> $(readlink "$p")"
    elif [ -f "$p" ]; then echo "file $(stat -f %Lp "$p") $(shasum -a 256 < "$p" | cut -d' ' -f1) $p"
    else echo "dir $p"
    fi
  done)
}
diff <(tree "$app") <(tree "$unpacked") >"$work/difference" || {
  head -20 "$work/difference" >&2
  fail 'the bundle in the image is not the one in the update archive'
}

codesign --verify --deep --strict --verbose=2 "$app" || fail "the bundle's signature does not hold"

if [ -z "$team" ]; then
  echo "::warning::$(basename "$app") is not signed for distribution (no team ID given) — an ad hoc build"
  exit 0
fi

requirement="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\""
codesign --verify --deep --strict -R="$requirement" "$app" || fail "the bundle is not a Developer ID signature of team $team"
codesign --verify -R="$requirement" "$image" || fail "the image is not a Developer ID signature of team $team"
xcrun stapler validate "$app" || fail 'the bundle carries no notarization ticket'
xcrun stapler validate "$image" || fail 'the image carries no notarization ticket'
spctl --assess --type execute "$app" || fail 'Gatekeeper refuses the bundle'
spctl --assess --type open --context context:primary-signature "$image" || fail 'Gatekeeper refuses the image'
echo "$(basename "$app"): Developer ID of team $team, notarized and stapled"
