#!/usr/bin/env bash
# Build the official Havoc Qt operator client on an Ubuntu desktop lab VM.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
offline=${DEIMUSTECH_OFFLINE_BUNDLE:-}
if [[ -n $offline ]]; then
  sudo dpkg -i "$offline"/debs/*.deb || sudo apt-get -f install -y --no-download
else
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git build-essential cmake python3-dev libfontconfig1 libglu1-mesa-dev libspdlog-dev libboost-all-dev libssl-dev qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools libqt5websockets5-dev qtdeclarative5-dev
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
if [[ -z $offline || ! -x ./havoc ]]; then make client-build; fi
echo 'Start the operator client with: /opt/deimustech/Havoc/havoc client'
echo 'Connect to 172.16.113.66 on TCP 40056 using your unique named operator account.'
