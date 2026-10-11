#!/usr/bin/env bash
# Run on a matching Internet-connected Ubuntu release before entering the air gap.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bundle=${1:-"$PWD/deimustech-c2-offline-bundle"}
mkdir -p "$bundle/debs" "$bundle/src"
mkdir -p "$bundle/toolchains" "$bundle/docker-debs"

packages=(git make build-essential cmake golang-go mingw-w64 nasm musl-tools libssl-dev
  python3-dev libfontconfig1 libglu1-mesa-dev libspdlog-dev libboost-all-dev
  qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools libqt5websockets5-dev
  qtdeclarative5-dev ca-certificates curl)
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "${packages[@]}"
sudo apt-get -y --download-only --reinstall install "${packages[@]}"
cp -a /var/cache/apt/archives/*.deb "$bundle/debs/"
"$script_dir/ensure_docker_engine.sh"
sudo apt-get -y --download-only --reinstall install \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
find /var/cache/apt/archives -maxdepth 1 -type f \( \
  -name 'docker-ce_*.deb' -o -name 'docker-ce-cli_*.deb' -o \
  -name 'containerd.io_*.deb' -o -name 'docker-buildx-plugin_*.deb' -o \
  -name 'docker-compose-plugin_*.deb' \) -exec cp -a {} "$bundle/docker-debs/" \;
case $(uname -m) in
  x86_64|amd64) go_archive=go1.22.12.linux-amd64.tar.gz; go_sha=4fa4f869b0f7fc6bb1eb2660e74657fbf04cdd290b5aef905585c86051b34d43 ;;
  aarch64|arm64) go_archive=go1.22.12.linux-arm64.tar.gz; go_sha=fd017e647ec28525e86ae8203236e0653242722a7436929b1f775744e26278e7 ;;
  *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
esac
curl -fL "https://go.dev/dl/$go_archive" -o "$bundle/toolchains/$go_archive"
printf '%s  %s\n' "$go_sha" "$bundle/toolchains/$go_archive" | sha256sum -c -
DEIMUSTECH_OFFLINE_BUNDLE="$bundle" "$script_dir/ensure_go_toolchain.sh"

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
(cd "$bundle/src/Havoc/teamserver" && GO111MODULE=on go mod tidy && GO111MODULE=on go mod download)
(cd "$bundle/src/Havoc" && make ts-build && make client-build)
(cd "$bundle/src/Mythic" && sudo make)
[[ -x "$bundle/src/Havoc/havoc" ]] || { echo 'Havoc build did not produce the expected launcher.' >&2; exit 1; }
[[ -x "$bundle/src/Mythic/mythic-cli" ]] || { echo 'Mythic build did not produce mythic-cli.' >&2; exit 1; }
cp -a "$script_dir"/*.sh "$script_dir"/*.py "$script_dir/lab.env" "$bundle/"
cat > "$bundle/README-OFFLINE.txt" <<'EOF'
Copy this entire directory to the air-gapped Ubuntu server. Use the same Ubuntu
release and CPU architecture used to create the bundle. Then run:
  export DEIMUSTECH_OFFLINE_BUNDLE="$PWD"
  ./install_teamserver.sh

Mythic is container based. On the connected staging host, complete one Mythic
start first, then run export_mythic_images_ubuntu.sh into this bundle. Without
mythic-images.tar, Mythic cannot start for the first time in a true air gap.
EOF
echo "Offline source/dependency bundle prepared at $bundle"
echo "Next: stage Mythic once online, then export its images into the bundle."
