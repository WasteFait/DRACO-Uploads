#!/usr/bin/env bash
# Destructively rebuild Mythic from a clean database, then complete the teamserver.
set -euo pipefail
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a sudo-capable user, not root.' >&2; exit 1; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lab.env"

admin_user=${DEIMUSTECH_MYTHIC_ADMIN_USER:-mythic_admin}
admin_password=${DEIMUSTECH_MYTHIC_ADMIN_PASSWORD:-DeimusTech-Mythic-Admin!}
operator_password=${DEIMUSTECH_OPERATOR_PASSWORD:-DeimusTech-Lab-Operator!}
if ((${#admin_password} < 12 || ${#operator_password} < 12)); then
  echo 'Mythic administrator and operator passwords must contain at least 12 characters.' >&2
  exit 2
fi

if [[ ${1:-} != --yes ]]; then
  echo 'WARNING: This permanently deletes the existing Mythic database, containers,' >&2
  echo 'volumes, installed services, payload records, users, operations and source tree.' >&2
  echo 'Havoc and unrelated Docker workloads are not removed.' >&2
  read -r -p 'Type REBUILD-MYTHIC to continue: ' confirmation
  [[ $confirmation == REBUILD-MYTHIC ]] || { echo 'Cancelled.'; exit 2; }
fi

mythic_root=/opt/deimustech/Mythic
if [[ -x $mythic_root/mythic-cli ]]; then
  (cd "$mythic_root" && sudo ./mythic-cli stop) || true
fi

mapfile -t mythic_containers < <(
  {
    sudo docker ps -aq --filter label=com.docker.compose.project=mythic
    sudo docker ps -aq --filter 'name=^/mythic_'
  } | awk 'NF && !seen[$0]++'
)
mythic_images=()
if ((${#mythic_containers[@]})); then
  mapfile -t mythic_images < <(
    sudo docker inspect --format '{{.Image}}' "${mythic_containers[@]}" |
      awk 'NF && !seen[$0]++'
  )
  sudo docker rm -f -v "${mythic_containers[@]}"
fi

mapfile -t mythic_volumes < <(
  {
    sudo docker volume ls -q --filter label=com.docker.compose.project=mythic
    sudo docker volume ls -q --filter name=mythic_
  } | awk '/^mythic_/ || NF {if(!seen[$0]++) print}'
)
((${#mythic_volumes[@]} == 0)) || sudo docker volume rm -f "${mythic_volumes[@]}"

mapfile -t mythic_networks < <(
  {
    sudo docker network ls -q --filter label=com.docker.compose.project=mythic
    sudo docker network ls -q --filter name=mythic
  } | awk 'NF && !seen[$0]++'
)
((${#mythic_networks[@]} == 0)) || sudo docker network rm "${mythic_networks[@]}" || true
for image_id in "${mythic_images[@]}"; do
  # Preserve an image if any unrelated remaining container references it.
  if [[ -z $(sudo docker ps -aq --filter "ancestor=$image_id") ]]; then
    sudo docker image rm -f "$image_id" || true
  fi
done

if [[ -e $mythic_root ]]; then
  [[ $mythic_root == /opt/deimustech/Mythic ]] || { echo 'Unexpected Mythic path; refusing removal.' >&2; exit 1; }
  sudo rm -rf --one-file-system "$mythic_root"
fi
sudo rm -f /var/lib/deimustech-c2/mythic-catalog-success.tsv \
  /var/lib/deimustech-c2/mythic-catalog-failures.tsv
sudo find /var/log/deimustech-c2 -maxdepth 1 -type f \
  -name 'mythic-catalog-*.log' -delete 2>/dev/null || true

sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" /etc/deimustech-c2
sudo tee /etc/deimustech-c2/mythic-admin.txt >/dev/null <<EOF
DeimusTech Mythic administrator
URL after lab networking: https://${TEAMSERVER_IP}:${MYTHIC_HTTPS_PORT}
Local URL: https://127.0.0.1:${MYTHIC_HTTPS_PORT}
Username: ${admin_user}
Password: ${admin_password}
EOF
sudo chmod 0600 /etc/deimustech-c2/mythic-admin.txt

export DEIMUSTECH_MYTHIC_ADMIN_USER=$admin_user
export DEIMUSTECH_MYTHIC_ADMIN_PASSWORD=$admin_password
export DEIMUSTECH_OPERATOR_PASSWORD=$operator_password
unset DEIMUSTECH_OFFLINE_BUNDLE

"$script_dir/install_teamserver.sh"

echo
echo 'Clean Mythic rebuild completed.'
echo 'Administrator credential file: /etc/deimustech-c2/mythic-admin.txt'
echo 'Operator credential file     : /etc/deimustech-c2/operator-accounts.txt'
echo "Mythic URL                   : https://${TEAMSERVER_IP}:${MYTHIC_HTTPS_PORT}"
echo "Mythic local URL             : https://127.0.0.1:${MYTHIC_HTTPS_PORT}"
