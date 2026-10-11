#!/usr/bin/env bash
# Verify and reassemble C2 bundle parts downloaded from a GitHub Release.
set -euo pipefail
parts_dir=$(realpath "${1:-$PWD}")
destination=$(realpath -m "${2:-$PWD/restored-c2-bundle}")
cd "$parts_dir"
sha256sum -c PART-SHA256SUMS.txt
mkdir -p "$destination"
archive="$destination/deimustech-c2-offline-bundle.tar.gz"
cat deimustech-c2-offline-bundle.tar.gz.*.part > "$archive"
(cd "$destination" && sha256sum -c "$parts_dir/ARCHIVE-SHA256SUMS.txt")
tar -C "$destination" -xzf "$archive"
echo "Restored bundle under $destination/deimustech-c2-offline-bundle"
