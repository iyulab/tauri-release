#!/usr/bin/env bash
# Packages a macOS app bundle for release: staples its notarization ticket when asked, then makes the
# compressed disk image a person opens (the bundle and a link to Applications) and the archive an
# update downloads (the same bundle, tarred). Runs no signing: whatever signature the bundle carries
# is what both hold.
#
#   image.sh --bundle <path/App.app> --out <dir> --volume <name> [--image <name.dmg>]
#            [--archive <name.tar.gz>] [--staple true|false]
#
# Prints image=<path> and archive=<path>.
set -euo pipefail

bundle='' out='' volume='' image='' archive='' staple=false
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) bundle=$2 ;;
    --out) out=$2 ;;
    --volume) volume=$2 ;;
    --image) image=$2 ;;
    --archive) archive=$2 ;;
    --staple) staple=$2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift 2
done
[ -d "$bundle" ] || { echo "no bundle at '$bundle'" >&2; exit 1; }
[ -n "$out" ] && [ -n "$volume" ] || { echo '--out and --volume are required' >&2; exit 2; }
bundle=${bundle%/}
name=$(basename "$bundle")
[ -n "$image" ] || image="${name%.app}.dmg"
[ -n "$archive" ] || archive="$name.tar.gz"
mkdir -p "$out"

if [ "$staple" = true ]; then
  xcrun stapler staple "$bundle"
fi

# The image: a folder holding the bundle and a link to Applications, made with hdiutil alone — no
# Finder, so it runs unattended and the same input gives the same content.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$bundle" "$staging/$name"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "$volume" -srcfolder "$staging" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$out/$image"

# The update archive: the bundle as it is, with its symbolic links and modes, and without the
# AppleDouble files macOS's tar would add for extended attributes.
COPYFILE_DISABLE=1 tar --no-mac-metadata -czf "$out/$archive" -C "$(dirname "$bundle")" "$name"

echo "image=$out/$image"
echo "archive=$out/$archive"
