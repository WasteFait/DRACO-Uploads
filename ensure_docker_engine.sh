#!/usr/bin/env bash
# Ensure a supported Docker Engine and Compose v2 are installed for Mythic.
set -euo pipefail

offline=${DEIMUSTECH_OFFLINE_BUNDLE:-}

docker_is_usable() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  local engine_major compose_major
  engine_major=$(sudo docker version --format '{{.Server.Version}}' 2>/dev/null | cut -d. -f1)
  compose_major=$(docker compose version --short 2>/dev/null | sed 's/^v//' | cut -d. -f1)
  [[ $engine_major =~ ^[0-9]+$ && $engine_major -ge 24 ]]
  [[ $compose_major =~ ^[0-9]+$ && $compose_major -ge 2 ]]
}

if docker_is_usable; then
  echo "Docker Engine $(sudo docker version --format '{{.Server.Version}}') and $(docker compose version) are ready."
  exit 0
fi

if [[ -n $offline ]]; then
  shopt -s nullglob
  debs=("$offline"/docker-debs/*.deb)
  ((${#debs[@]})) || { echo "Offline bundle has no docker-debs/*.deb files." >&2; exit 1; }
  sudo dpkg -i "${debs[@]}" || sudo apt-get -f install -y --no-download
else
  . /etc/os-release
  [[ ${ID:-} == ubuntu ]] || { echo 'This installer supports Ubuntu only.' >&2; exit 1; }
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  arch=$(dpkg --print-architecture)
  codename=${UBUNTU_CODENAME:-$VERSION_CODENAME}
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' "$codename" "$arch" | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
  sudo apt-get update
  # Package removal does not delete images, containers, volumes, or /var/lib/docker.
  sudo apt-get remove -y docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

sudo systemctl enable --now docker
docker_is_usable || { echo 'Docker installation completed, but Engine >=24 and Compose v2 are not usable.' >&2; exit 1; }
sudo docker version
docker compose version
