#!/usr/bin/env bash
# Install official Mythic core on a dedicated Ubuntu lab VM.
set -euo pipefail
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a sudo-capable user, not root.' >&2; exit 1; fi
offline=${DEIMUSTECH_OFFLINE_BUNDLE:-}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lab.env"
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
if [[ -n ${DEIMUSTECH_MYTHIC_ADMIN_USER:-} ]]; then
  sudo ./mythic-cli config set mythic_admin_user "$DEIMUSTECH_MYTHIC_ADMIN_USER"
fi
if [[ -n ${DEIMUSTECH_MYTHIC_ADMIN_PASSWORD:-} ]]; then
  sudo ./mythic-cli config set mythic_admin_password "$DEIMUSTECH_MYTHIC_ADMIN_PASSWORD"
fi
# Bootstrap startup is temporarily open so the combined installer can discover
# Docker's bridge gateway. install_teamserver.sh immediately replaces this with
# loopback, the exact bridge gateway /32, and the operator CIDR.
sudo ./mythic-cli config set allowed_ip_blocks '0.0.0.0/0'
sudo ./mythic-cli config set nginx_bind_localhost_only false
sudo ./mythic-cli config set nginx_use_ipv4 true
sudo ./mythic-cli config set default_operation_name 'DeimusTech Operations'
echo
echo 'ALLOWED_IP_BLOCKS is temporarily open for first-start bridge discovery.'
echo 'Mythic nginx is configured on IPv4 beyond loopback for the operator VLAN.'
echo 'The combined teamserver installer will now start Mythic and provision operator accounts.'
echo 'Operator devices connect with a browser to the HTTPS URL reported by mythic-cli status.'
