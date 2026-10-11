#!/usr/bin/env bash
# Install official Mythic core on a dedicated Ubuntu lab VM.
set -euo pipefail
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a sudo-capable user, not root.' >&2; exit 1; fi
offline=${DEIMUSTECH_OFFLINE_BUNDLE:-}
if [[ -n $offline ]]; then
  sudo dpkg -i "$offline"/debs/*.deb || sudo apt-get -f install -y --no-download
else
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git make ca-certificates curl
fi
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
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  if [[ -n $offline ]]; then
    echo 'Docker is missing after offline package installation.' >&2
    exit 1
  else
    echo 'Docker is missing; running Mythic official Ubuntu Docker installer.'
    sudo ./install_docker_ubuntu.sh
  fi
fi
if [[ -n $offline ]]; then
  [[ -f $offline/mythic-images.tar ]] || { echo 'Offline bundle is missing mythic-images.tar.' >&2; exit 1; }
  (cd "$offline" && sha256sum -c mythic-images.tar.sha256)
  sudo docker load -i "$offline/mythic-images.tar"
fi
if [[ -z $offline || ! -x ./mythic-cli ]]; then sudo make; fi
sudo ./mythic-cli status
sudo ./mythic-cli config set allowed_ip_blocks 172.16.113.0/24
echo
echo 'ALLOWED_IP_BLOCKS has been restricted to 172.16.113.0/24.'
echo 'Then start Mythic with: cd /opt/deimustech/Mythic && sudo ./mythic-cli start'
echo 'Operator devices connect with a browser to the HTTPS URL reported by mythic-cli status.'
