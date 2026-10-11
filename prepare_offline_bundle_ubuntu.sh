#!/usr/bin/env bash
# Run on a matching Internet-connected Ubuntu release before entering the air gap.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bundle=${1:-"$PWD/deimustech-c2-offline-bundle"}
mkdir -p "$bundle/debs" "$bundle/src"

packages=(git make build-essential cmake golang-go mingw-w64 nasm musl-tools libssl-dev
  python3-dev libfontconfig1 libglu1-mesa-dev libspdlog-dev libboost-all-dev
  qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools libqt5websockets5-dev
  qtdeclarative5-dev ca-certificates curl docker.io docker-compose-v2)
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "${packages[@]}"
sudo apt-get -y --download-only --reinstall install "${packages[@]}"
cp -a /var/cache/apt/archives/*.deb "$bundle/debs/"

if [[ ! -d "$bundle/src/Havoc/.git" ]]; then
  git clone --recurse-submodules https://github.com/HavocFramework/Havoc.git "$bundle/src/Havoc"
else
  git -C "$bundle/src/Havoc" pull --ff-only
  git -C "$bundle/src/Havoc" submodule update --init --recursive
fi
if [[ ! -d "$bundle/src/Mythic/.git" ]]; then
  git clone --depth 1 https://github.com/its-a-feature/Mythic.git "$bundle/src/Mythic"
else
  git -C "$bundle/src/Mythic" pull --ff-only
fi

# Preserve exact source revisions for repeatability.
git -C "$bundle/src/Havoc" rev-parse HEAD > "$bundle/HAVOC_COMMIT"
git -C "$bundle/src/Mythic" rev-parse HEAD > "$bundle/MYTHIC_COMMIT"
(cd "$bundle/src/Havoc" && make ts-build && make client-build)
(cd "$bundle/src/Mythic" && sudo make)
[[ -x "$bundle/src/Havoc/havoc" ]] || { echo 'Havoc build did not produce the expected launcher.' >&2; exit 1; }
[[ -x "$bundle/src/Mythic/mythic-cli" ]] || { echo 'Mythic build did not produce mythic-cli.' >&2; exit 1; }
cp -a "$script_dir"/*.sh "$script_dir"/*.py "$script_dir/lab.env" "$bundle/"
cat > "$bundle/README-OFFLINE.txt" <<'EOF'
Copy this entire directory to the air-gapped Ubuntu server. Use the same Ubuntu
release and CPU architecture used to create the bundle. Then run:
  export DEIMUSTECH_OFFLINE_BUNDLE="$PWD"
  ./install_c2_teamserver_ubuntu.sh

Mythic is container based. On the connected staging host, complete one Mythic
start first, then run export_mythic_images_ubuntu.sh into this bundle. Without
mythic-images.tar, Mythic cannot start for the first time in a true air gap.
EOF
echo "Offline source/dependency bundle prepared at $bundle"
echo "Next: stage Mythic once online, then export its images into the bundle."
