#!/usr/bin/env bash
# Export already-pulled Mythic images for transfer into an air gap.
set -euo pipefail
bundle=${1:-"$PWD/deimustech-c2-offline-bundle"}
mkdir -p "$bundle"
mapfile -t images < <(docker image ls --format '{{.Repository}}:{{.Tag}}' | awk '$1 ~ /mythic|itsafeature|ghcr.io\/mythic/ {print}' | sort -u)
if ((${#images[@]} == 0)); then
  echo 'No Mythic images found. Start Mythic once on this connected staging host first.' >&2
  exit 1
fi
docker save -o "$bundle/mythic-images.tar" "${images[@]}"
docker image inspect "${images[@]}" --format '{{index .RepoDigests 0}}' > "$bundle/mythic-image-digests.txt"
sha256sum "$bundle/mythic-images.tar" > "$bundle/mythic-images.tar.sha256"
echo "Exported ${#images[@]} image(s) to $bundle/mythic-images.tar"

