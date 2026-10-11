#!/usr/bin/env bash
# Package a prepared C2 offline bundle as GitHub Release-compatible parts.
set -euo pipefail
bundle=${1:-}
output=${2:-"$PWD/github-c2-release"}
if [[ -z $bundle || ! -d $bundle ]]; then
  echo "Usage: $0 /path/to/deimustech-c2-offline-bundle [output-directory]" >&2
  exit 2
fi
for required in src/Havoc/havoc src/Mythic/mythic-cli mythic-images.tar mythic-images.tar.sha256; do
  [[ -e $bundle/$required ]] || { echo "Bundle is missing $required" >&2; exit 1; }
done
mkdir -p "$output"
archive="$output/deimustech-c2-offline-bundle.tar.gz"
tar -C "$(dirname "$bundle")" -czf "$archive" "$(basename "$bundle")"
(
  cd "$output"
  sha256sum deimustech-c2-offline-bundle.tar.gz > ARCHIVE-SHA256SUMS.txt
)
split -b 1900M -d -a 2 --additional-suffix=.part "$archive" "$output/deimustech-c2-offline-bundle.tar.gz."
(
  cd "$output"
  sha256sum ./*.part > PART-SHA256SUMS.txt
)
echo "GitHub Release parts created in $output"
echo 'Upload every .part file plus ARCHIVE-SHA256SUMS.txt and PART-SHA256SUMS.txt.'
