#!/usr/bin/env bash
# Recover Mythic catalog disk space while preserving a small useful service set.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mythic_dir=${MYTHIC_DIR:-/opt/deimustech/Mythic}
target_free_gib=${TARGET_FREE_GIB:-15}
reinstall_buffer_gib=${REINSTALL_BUFFER_GIB:-5}
work_target_gib=$((target_free_gib + reinstall_buffer_gib))
state_catalog=/var/lib/deimustech-c2/mythic-catalog-success.tsv
bundled_catalog=$script_dir/mythic_catalog.tsv

if [[ ${EUID} -eq 0 ]]; then
  echo 'Run this script as the normal sudo-capable account, not as root.' >&2
  exit 1
fi
if [[ ! $target_free_gib =~ ^[0-9]+$ ]] || ((target_free_gib < 4)); then
  echo 'TARGET_FREE_GIB must be an integer of at least 4.' >&2
  exit 1
fi
if [[ ! $reinstall_buffer_gib =~ ^[0-9]+$ ]]; then
  echo 'REINSTALL_BUFFER_GIB must be a non-negative integer.' >&2
  exit 1
fi
if [[ ! -x $mythic_dir/mythic-cli ]]; then
  echo "Missing executable: $mythic_dir/mythic-cli" >&2
  exit 1
fi

if [[ -s $state_catalog ]]; then
  catalog=$state_catalog
elif [[ -s $bundled_catalog ]]; then
  catalog=$bundled_catalog
else
  echo 'No Mythic catalog record or bundled manifest was found.' >&2
  exit 1
fi

available_kib() {
  df -Pk / | awk 'NR == 2 {print $4}'
}

show_space() {
  df -h /
  sudo docker system df || true
}

keep_service() {
  case "${1,,}" in
    apollo|poseidon|merlin|thanatos|apfell|http) return 0 ;;
    *) return 1 ;;
  esac
}

echo 'This recovery preserves: Apollo, Poseidon, Merlin, Thanatos, apfell, and HTTP.'
echo "Cleanup target before restoration: ${work_target_gib} GiB free."
echo "Requested final reserve: ${target_free_gib} GiB free."
echo 'Docker volumes and the Mythic PostgreSQL database will not be removed.'
show_space

sudo -v
echo 'Removing disposable package, journal, container, image, and build cache...'
sudo apt-get clean
sudo journalctl --vacuum-size=100M || true
sudo docker container prune -f
sudo docker image prune -f
sudo docker builder prune -af

target_kib=$((work_target_gib * 1024 * 1024))
removed=0
while IFS=$'\t' read -r category repository _rest; do
  [[ -n ${category:-} && $category != \#* && -n ${repository:-} ]] || continue
  if (( $(available_kib) >= target_kib )); then
    break
  fi
  service=${repository##*/}
  service=${service%.git}
  if keep_service "$service"; then
    echo "Keeping selected service: $service"
    continue
  fi
  echo "Removing catalog service: $service"
  mapfile -t service_images < <(
    sudo docker ps -a \
      --filter "label=com.docker.compose.service=${service,,}" \
      --format '{{.Image}}' | awk 'NF && !seen[$0]++'
  )
  (
    cd "$mythic_dir"
    sudo ./mythic-cli remove "$service"
  ) || echo "NOTICE: $service was already absent or could not be removed from Compose."
  sudo docker container prune -f >/dev/null
  if ((${#service_images[@]})); then
    sudo docker image rm "${service_images[@]}" >/dev/null 2>&1 || true
  fi
  sudo docker image prune -f >/dev/null
  removed=$((removed + 1))
  printf 'Free space after %s: ' "$service"
  df -h --output=avail / | tail -n 1
done < "$catalog"

if (( $(available_kib) < target_kib )); then
  echo "Unable to reach the ${work_target_gib} GiB restoration target using non-selected catalog services." >&2
  echo 'No selected services were removed. Current state:' >&2
  show_space
  exit 1
fi

echo 'Restoring the selected service definitions. Existing entries are refreshed with --force.'
keep_repositories=(
  'https://github.com/MythicC2Profiles/http'
  'https://github.com/MythicAgents/Apollo'
  'https://github.com/MythicAgents/poseidon'
  'https://github.com/MythicAgents/merlin'
  'https://github.com/MythicAgents/thanatos'
  'https://github.com/MythicAgents/apfell'
)
for repository in "${keep_repositories[@]}"; do
  echo "Installing or repairing: $repository"
  (
    cd "$mythic_dir"
    sudo ./mythic-cli install github "$repository" --force
  )
done

echo 'Starting Mythic and validating the resulting service set...'
(
  cd "$mythic_dir"
  sudo ./mythic-cli start
  sudo ./mythic-cli status -v
)

sudo docker container prune -f >/dev/null
sudo docker image prune -f >/dev/null
sudo docker builder prune -af >/dev/null

final_kib=$(available_kib)
echo
echo "Removed or detached $removed non-selected catalog services."
show_space
if ((final_kib < target_free_gib * 1024 * 1024)); then
  echo "WARNING: restoration completed, but less than ${target_free_gib} GiB remains." >&2
  echo 'Review `sudo docker system df -v`; this script will not delete Mythic data volumes.' >&2
  exit 2
fi
echo "Recovery complete with at least ${target_free_gib} GiB available."
