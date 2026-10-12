#!/usr/bin/env bash
set -euo pipefail

# Package an archived iOS app into an unsigned IPA suitable for sideloading.
# Usage: scripts/package-unsigned-ipa.sh <archive-or-app-path> <output-ipa>

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <archive-or-app-path> <output-ipa>" >&2
  exit 2
fi

source_path="$1"
output_ipa="$2"
app_path=""

if [[ -d "$source_path/Products/Applications" ]]; then
  app_path="$(find "$source_path/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
elif [[ "$source_path" == *.app && -d "$source_path" ]]; then
  app_path="$source_path"
fi

if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "Could not find an .app in archive or app path: $source_path" >&2
  exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")
if [[ "$bundle_id" != "com.hesm4tt.digify" ]]; then
  echo "Unexpected bundle identifier '$bundle_id' (expected com.hesm4tt.digify)" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_ipa")"
output_ipa="$(cd "$(dirname "$output_ipa")" && pwd)/$(basename "$output_ipa")"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$staging_dir/Payload"
ditto "$app_path" "$staging_dir/Payload/Digify.app"
(cd "$staging_dir" && /usr/bin/zip -qry "$output_ipa" Payload)

echo "Created unsigned IPA: $output_ipa"
