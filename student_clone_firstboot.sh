#!/usr/bin/env bash
# Assign ops-01..ops-99 from 172.16.113.101..199 on a cloned workstation.
set -euo pipefail

state_dir=/var/lib/deimustech
stamp=$state_dir/operator-clone-personalized
[[ -e $stamp ]] && exit 0

install -d -m 0755 "$state_dir"

# Address assignment may finish after network-online.target, especially with DHCP
# or vCenter guest customization. Wait up to two minutes for exactly one lab IP.
selected_ip=
for _ in $(seq 1 60); do
  mapfile -t candidates < <(
    ip -4 -o address show scope global |
      awk '{print $4}' |
      cut -d/ -f1 |
      awk -F. '$1==172 && $2==16 && $3==113 && $4>=101 && $4<=199'
  )
  if ((${#candidates[@]} == 1)); then
    selected_ip=${candidates[0]}
    break
  elif ((${#candidates[@]} > 1)); then
    echo 'More than one address in 172.16.113.101-199 is assigned; refusing ambiguous personalization.' >&2
    exit 1
  fi
  sleep 2
done

if [[ -z $selected_ip ]]; then
  echo 'No address in 172.16.113.101-199 appeared within 120 seconds; will retry next boot.' >&2
  exit 1
fi

last_octet=${selected_ip##*.}
operator_number=$((10#$last_octet - 100))
printf -v new_hostname 'ops-%02d' "$operator_number"

hostnamectl set-hostname "$new_hostname"
if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
  sed -i -E "s/^(127\\.0\\.1\\.1)[[:space:]].*/\\1 ${new_hostname}/" /etc/hosts
else
  printf '127.0.1.1 %s\n' "$new_hostname" >> /etc/hosts
fi

cat > "$stamp" <<EOF
HOSTNAME=$new_hostname
ASSIGNED_IP=$selected_ip
PERSONALIZED_AT=$(date --iso-8601=seconds)
EOF
chmod 0644 "$stamp"
systemctl disable deimustech-clone-personalize.service >/dev/null 2>&1 || true
logger -t deimustech-clone "Personalized this operator clone as $new_hostname from $selected_ip"
echo "Personalized this operator clone as $new_hostname from $selected_ip"
