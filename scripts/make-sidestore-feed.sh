#!/usr/bin/env bash
set -euo pipefail

# Create the SideStore source JSON for a released Digify IPA.
# Usage: scripts/make-sidestore-feed.sh <ipa> <output-json> [release-tag]

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <ipa> <output-json> [release-tag]" >&2
  exit 2
fi

ipa_path="$1"
output_json="$2"
release_tag="${3:-}"
repo="hesm4tt/Digify"
bundle_id="com.hesm4tt.digify"
ipa_name="$(basename "$ipa_path")"

[[ -f "$ipa_path" ]] || { echo "IPA not found: $ipa_path" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
unzip -q "$ipa_path" 'Payload/*.app/Info.plist' -d "$staging_dir"
info_plist="$(find "$staging_dir/Payload" -maxdepth 3 -name Info.plist -print -quit)"
[[ -n "$info_plist" ]] || { echo "No app Info.plist found in $ipa_path" >&2; exit 1; }

actual_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")
[[ "$actual_bundle_id" == "$bundle_id" ]] || {
  echo "Unexpected bundle identifier '$actual_bundle_id' (expected $bundle_id)" >&2
  exit 1
}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
minimum_os=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$info_plist" 2>/dev/null || true)
[[ -n "$minimum_os" ]] || minimum_os="16.0"
photo_library_description=$(/usr/libexec/PlistBuddy -c 'Print :NSPhotoLibraryUsageDescription' "$info_plist")
photo_add_description=$(/usr/libexec/PlistBuddy -c 'Print :NSPhotoLibraryAddUsageDescription' "$info_plist")
release_date="$(date -u +%F)"
ipa_size="$(stat -f '%z' "$ipa_path")"
download_url="https://github.com/${repo}/releases/latest/download/${ipa_name}"
feed_url="https://github.com/${repo}/releases/latest/download/digify.json"
icon_url="https://raw.githubusercontent.com/${repo}/main/docs/assets/icon.png"

mkdir -p "$(dirname "$output_json")"
jq -n \
  --arg releaseTag "$release_tag" \
  --arg feedURL "$feed_url" \
  --arg downloadURL "$download_url" \
  --arg iconURL "$icon_url" \
  --arg date "$release_date" \
  --arg version "$version" \
  --arg buildVersion "$build_version" \
  --arg minOSVersion "$minimum_os" \
  --arg photoLibraryDescription "$photo_library_description" \
  --arg photoAddDescription "$photo_add_description" \
  --argjson size "$ipa_size" \
  '{
    name: "Digify",
    identifier: "com.hesm4tt.digify.source",
    sourceURL: $feedURL,
    apps: [{
      name: "Digify",
      bundleIdentifier: "com.hesm4tt.digify",
      developerName: "hesm4tt",
      subtitle: "Pocket camera color, full-resolution exports",
      localizedDescription: "Give HEIF and supported RAW photos a Canon PowerShot ELPH 360 HS A-inspired look. Photos are processed on your device.",
      iconURL: $iconURL,
      tintColor: "#E7A64B",
      category: "photo-video",
      appPermissions: {
        entitlements: [],
        privacy: {
          NSPhotoLibraryUsageDescription: $photoLibraryDescription,
          NSPhotoLibraryAddUsageDescription: $photoAddDescription
        }
      },
      versions: [{
        version: $version,
        buildVersion: $buildVersion,
        date: $date,
        downloadURL: $downloadURL,
        size: $size,
        minOSVersion: $minOSVersion,
        localizedDescription: (if $releaseTag == "" then "Digify release." else "Digify " + $releaseTag + "." end)
      }]
    }]
  }' > "$output_json"

jq -e '
  (.apps | length == 1) and
  (.apps[0].category == "photo-video") and
  (.apps[0].appPermissions.entitlements == []) and
  (.apps[0].appPermissions.privacy | has("NSPhotoLibraryUsageDescription") and has("NSPhotoLibraryAddUsageDescription")) and
  (.apps[0].versions | length == 1 and (.[0].buildVersion | type == "string"))
' "$output_json" >/dev/null

echo "Created SideStore feed: $output_json"
