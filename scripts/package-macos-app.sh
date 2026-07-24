#!/bin/zsh
set -euo pipefail

if (( $# != 2 )) || [[ "$1" != "--install-dir" ]]; then
  print -u2 "Usage: $0 --install-dir <absolute-directory>"
  exit 64
fi

install_dir="$2"
if [[ "$install_dir" != /* ]] || [[ "$install_dir" == "/" ]]; then
  print -u2 "WWMD packaging requires an explicit absolute install directory."
  exit 64
fi

repo_root="${0:A:h:h}"
bundle_path="$install_dir/WWMD.app"
if [[ -e "$bundle_path" ]]; then
  print -u2 "Refusing to replace existing app bundle: $bundle_path"
  exit 73
fi

mkdir -p "$install_dir"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/wwmd-app.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
temporary_bundle="$temporary_root/WWMD.app"

cd "$repo_root"
swift build -c release --product WWMDApp
binary_directory="$(swift build -c release --show-bin-path)"
mkdir -p "$temporary_bundle/Contents/MacOS"
cp "$repo_root/Packaging/Info.plist" "$temporary_bundle/Contents/Info.plist"
cp "$binary_directory/WWMDApp" "$temporary_bundle/Contents/MacOS/WWMD"
chmod 755 "$temporary_bundle/Contents/MacOS/WWMD"
codesign --force --sign - --timestamp=none "$temporary_bundle"
mv "$temporary_bundle" "$bundle_path"

print "Installed WWMD at $bundle_path"
print "Launch with: open \"$bundle_path\""
