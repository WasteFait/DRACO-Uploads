#!/usr/bin/env bash
# Run once on every cloned Ubuntu student workstation before handing it out.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lab.env"
student_id=${1:-}
if [[ ! $student_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,31}$ ]]; then
  echo "Usage: $0 STUDENT_ID [STATIC_LAST_OCTET]" >&2
  exit 2
fi
safe_id=$(printf '%s' "$student_id" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')
hostname="dt-student-${safe_id}"
identity_file="$HOME/.config/deimustech/student.env"
if [[ -e $identity_file ]]; then
  echo "This clone is already personalized ($identity_file exists). Refusing to replace its identity." >&2
  exit 1
fi

sudo hostnamectl set-hostname "$hostname"
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_*
sudo systemd-machine-id-setup
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id
sudo ssh-keygen -A

install -d -m 0700 "$HOME/.config/deimustech"
identity=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
cat > "$identity_file" <<EOF
STUDENT_ID=$student_id
WORKSTATION_ID=$identity
TEAMSERVER_IP=$TEAMSERVER_IP
HAVOC_OPERATOR_PORT=$HAVOC_OPERATOR_PORT
MYTHIC_HTTPS_PORT=$MYTHIC_HTTPS_PORT
EOF
chmod 0600 "$identity_file"

if [[ -n ${2:-} ]]; then
  last_octet=$2
  if [[ ! $last_octet =~ ^[0-9]+$ ]] || ((last_octet < 2 || last_octet > 254 || last_octet == 66)); then
    echo 'STATIC_LAST_OCTET must be 2-254 and cannot be 66 (the teamserver).' >&2
    exit 2
  fi
  echo "Requested host address: 172.16.113.${last_octet}/${TEAMSERVER_PREFIX}"
  if [[ -n ${3:-} ]]; then
    nm_connection=$3
    sudo nmcli connection modify "$nm_connection" ipv4.method manual \
      ipv4.addresses "172.16.113.${last_octet}/${TEAMSERVER_PREFIX}"
    sudo nmcli connection up "$nm_connection"
    echo "Applied address to NetworkManager connection: $nm_connection"
  else
    echo 'Apply it after confirming the NetworkManager connection name.'
    echo "Use nmcli to assign 172.16.113.${last_octet}/${TEAMSERVER_PREFIX}; do not rerun clone personalization."
  fi
fi
echo "Clone personalized as $hostname with workstation ID $identity"
echo "Havoc login : ${TEAMSERVER_IP}:${HAVOC_OPERATOR_PORT} using the named roster account"
echo "Mythic login: https://${TEAMSERVER_IP}:${MYTHIC_HTTPS_PORT} using the matching named account"
