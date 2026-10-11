#!/usr/bin/env bash
# Install/build the official Havoc teamserver on a dedicated Ubuntu lab VM.
set -euo pipefail
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a sudo-capable user, not root.' >&2; exit 1; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
offline=${DEIMUSTECH_OFFLINE_BUNDLE:-}
if [[ -n $offline ]]; then
  sudo dpkg -i "$offline"/debs/*.deb || sudo apt-get -f install -y --no-download
else
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git build-essential cmake golang-go mingw-w64 nasm musl-tools libssl-dev
fi
"$script_dir/ensure_go_toolchain.sh"
sudo install -d -o "$USER" -g "$USER" /opt/deimustech
if [[ -n $offline ]]; then
  [[ -d $offline/src/Havoc ]] || { echo 'Offline bundle is missing src/Havoc.' >&2; exit 1; }
  cp -a "$offline/src/Havoc/." /opt/deimustech/Havoc/
elif [[ ! -d /opt/deimustech/Havoc/.git ]]; then
  git clone --recurse-submodules https://github.com/HavocFramework/Havoc.git /opt/deimustech/Havoc
else
  git -C /opt/deimustech/Havoc pull --ff-only
  git -C /opt/deimustech/Havoc submodule update --init --recursive
fi
cd /opt/deimustech/Havoc
if [[ -z $offline || ! -x ./havoc ]]; then
  (cd teamserver && GO111MODULE=on go mod tidy && GO111MODULE=on go mod download)
  make ts-build
fi
echo
echo 'Havoc teamserver built. The combined installer will generate its operator profile'
echo 'and install/start the persistent deimustech-havoc systemd service.'
echo 'Do not expose TCP 40056 to the Internet.'
