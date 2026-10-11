#!/usr/bin/env bash
# Install official Mythic core on a dedicated Ubuntu lab VM.
set -euo pipefail
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a sudo-capable user, not root.' >&2; exit 1; fi
offline=${DEIMUSTECH_OFFLINE_BUNDLE:-}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -n $offline ]]; then
  sudo dpkg -i "$offline"/debs/*.deb || sudo apt-get -f install -y --no-download
else
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git make ca-certificates curl
fi
DEIMUSTECH_OFFLINE_BUNDLE="$offline" "$script_dir/ensure_docker_engine.sh"
sudo install -d -o "$USER" -g "$USER" /opt/deimustech
if [[ -n $offline ]]; then
  [[ -d $offline/src/Mythic ]] || { echo 'Offline bundle is missing src/Mythic.' >&2; exit 1; }
  cp -a "$offline/src/Mythic/." /opt/deimustech/Mythic/
elif [[ ! -d /opt/deimustech/Mythic/.git ]]; then
  git clone --depth 1 https://github.com/its-a-feature/Mythic.git /opt/deimustech/Mythic
else
  git -C /opt/deimustech/Mythic pull --ff-only
fi
cd /opt/deimustech/Mythic
if [[ -n $offline ]]; then
  [[ -f $offline/mythic-images.tar ]] || { echo 'Offline bundle is missing mythic-images.tar.' >&2; exit 1; }
  (cd "$offline" && sha256sum -c mythic-images.tar.sha256)
  sudo docker load -i "$offline/mythic-images.tar"
fi
if [[ -z $offline || ! -x ./mythic-cli ]]; then sudo make; fi
sudo ./mythic-cli status
sudo ./mythic-cli config set allowed_ip_blocks 172.16.113.0/24
sudo ./mythic-cli config set default_operation_name 'DeimusTech Operations'
echo
echo 'ALLOWED_IP_BLOCKS has been restricted to 172.16.113.0/24.'
echo 'The combined teamserver installer will now start Mythic and provision operator accounts.'
echo 'Operator devices connect with a browser to the HTTPS URL reported by mythic-cli status.'
