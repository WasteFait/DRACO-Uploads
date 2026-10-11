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

show_versions() {
  echo "Docker executable: $(command -v docker 2>/dev/null || echo missing)"
  echo "Docker client: $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo unavailable)"
  echo "Docker server: $(sudo docker version --format '{{.Server.Version}}' 2>/dev/null || echo unavailable)"
  echo "Compose: $(docker compose version --short 2>/dev/null || echo unavailable)"
}

if docker_is_usable; then
  echo "Docker Engine $(sudo docker version --format '{{.Server.Version}}') and $(docker compose version) are ready."
  exit 0
fi

echo 'Docker is missing or the running daemon is older than the DeimusTech baseline (Engine 24+, Compose v2).'
show_versions

if [[ -n $offline ]]; then
  shopt -s nullglob
  debs=("$offline"/docker-debs/*.deb)
  ((${#debs[@]})) || { echo "Offline bundle has no docker-debs/*.deb files." >&2; exit 1; }
  sudo dpkg -i "${debs[@]}" || sudo apt-get -f install -y --no-download
else
  . /etc/os-release
  [[ ${ID:-} == ubuntu ]] || { echo 'This installer supports Ubuntu only.' >&2; exit 1; }
  # Quarantine prior Docker entries before apt-get update; stale keys or two
  # different Signed-By values otherwise prevent APT from refreshing at all.
  for old_source in /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources; do
    if [[ -e $old_source ]]; then
      sudo mv "$old_source" "${old_source}.disabled"
    fi
  done
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  # Use a binary keyring for compatibility with older supported APT releases.
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
    sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  arch=$(dpkg --print-architecture)
  codename=${UBUNTU_CODENAME:-$VERSION_CODENAME}
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' "$arch" "$codename" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  apt-cache show docker-ce >/dev/null 2>&1 || {
    echo "Docker CE has no package candidate for Ubuntu codename '$codename' and architecture '$arch'." >&2
    echo 'Review apt-get update output, the system clock, and whether this Ubuntu release is supported.' >&2
    exit 1
  }
  # Package removal does not delete images, containers, volumes, or /var/lib/docker.
  sudo apt-get remove -y docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

sudo systemctl daemon-reload
sudo systemctl enable docker
# An upgraded binary does not guarantee that the already-running daemon was
# replaced. Restart containerd and Docker explicitly before checking Server.Version.
sudo systemctl restart containerd
sudo systemctl restart docker
hash -r
if ! docker_is_usable; then
  echo 'Docker packages were installed, but the active daemon is still below Engine 24 or Compose v2 is unavailable.' >&2
  show_versions >&2
  echo 'Check for a competing Snap install with: snap list docker' >&2
  echo 'Check selected packages with: apt-cache policy docker-ce docker.io containerd.io' >&2
  exit 1
fi
sudo docker version
docker compose version
