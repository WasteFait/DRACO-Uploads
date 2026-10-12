#!/usr/bin/env bash
# Single entry point for the DeimusTech combined Havoc/Mythic teamserver.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lab.env"

if [[ ${EUID} -eq 0 ]]; then
  echo 'Run as a sudo-capable user, not root.' >&2
  exit 1
fi
lab_address_status='configured'
if ! ip -4 -o addr show | awk '{print $4}' | grep -qx "${TEAMSERVER_IP}/${TEAMSERVER_PREFIX}"; then
  lab_address_status="not currently assigned; add ${TEAMSERVER_IP}/${TEAMSERVER_PREFIX} before student access"
  echo "WARNING: ${TEAMSERVER_IP}/${TEAMSERVER_PREFIX} is not currently assigned. Installation will continue." >&2
fi

export DEIMUSTECH_OFFLINE_BUNDLE=${DEIMUSTECH_OFFLINE_BUNDLE:-}
"$script_dir/install_havoc_teamserver_ubuntu.sh"
"$script_dir/install_mythic_server_ubuntu.sh"

sudo install -d -m 0750 -o "$USER" -g "$USER" /etc/deimustech-c2
sudo install -m 0644 "$script_dir/lab.env" /etc/deimustech-c2/lab.env
cd /opt/deimustech/Mythic
sudo ./mythic-cli start

mapfile -t mythic_networks < <(
  sudo docker inspect mythic_nginx mythic_graphql mythic_server \
    --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' 2>/dev/null |
    awk 'NF && !seen[$0]++'
)
if ((${#mythic_networks[@]} == 0)); then
  echo 'Unable to determine Mythic internal Docker networks.' >&2
  echo 'Inspect them with: sudo docker inspect mythic_nginx mythic_graphql mythic_server' >&2
  exit 1
fi
mythic_allowed="127.0.0.1/32,${MYTHIC_ADDITIONAL_ALLOWED_CIDRS},${OPERATOR_CIDR}"
for network in "${mythic_networks[@]}"; do
  mapfile -t network_subnets < <(
    sudo docker network inspect "$network" \
      --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' 2>/dev/null |
      awk 'NF && !seen[$0]++'
  )
  if ((${#network_subnets[@]} == 0)); then
    echo "Unable to determine subnet for Mythic Docker network: $network" >&2
    exit 1
  fi
  for subnet in "${network_subnets[@]}"; do
    mythic_allowed+=",${subnet}"
  done
done
sudo ./mythic-cli config set allowed_ip_blocks "$mythic_allowed"
sudo ./mythic-cli restart
echo "Mythic client and internal-service allowlist: $mythic_allowed"

cd "$script_dir"
echo 'Provisioning DeimusTech Mythic and Havoc operator accounts...'
DEIMUSTECH_HAVOC_BIND_HOST="$HAVOC_BIND_HOST" ./provision_default_operators.py

havoc_user=$USER
havoc_group=$(id -gn)
sudo tee /etc/systemd/system/deimustech-havoc.service >/dev/null <<EOF
[Unit]
Description=DeimusTech Havoc Teamserver
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$havoc_user
Group=$havoc_group
WorkingDirectory=/opt/deimustech/Havoc
ExecStart=/opt/deimustech/Havoc/havoc server --profile /opt/deimustech/Havoc/profiles/deimustech-lab.yaotl -v
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now deimustech-havoc.service
sudo systemctl is-active --quiet deimustech-havoc.service || {
  echo 'Havoc did not remain active. Review: sudo journalctl -u deimustech-havoc -n 100 --no-pager' >&2
  exit 1
}

if [[ -n $DEIMUSTECH_OFFLINE_BUNDLE ]]; then
  catalog_status='skipped in offline mode (catalog repositories/images are not in the base bundle)'
elif ! "$script_dir/install_mythic_catalog.sh"; then
  catalog_status='completed with one or more catalog failures; see /var/lib/deimustech-c2/mythic-catalog-failures.tsv'
else
  catalog_status='complete'
fi

echo 'Running integrated teamserver health checks...'
cd /opt/deimustech/Mythic
sudo ./mythic-cli status
sudo systemctl is-active --quiet deimustech-havoc.service
curl -ksS --connect-timeout 10 -o /dev/null "https://127.0.0.1:${MYTHIC_HTTPS_PORT}/"
ss -lnt | awk '{print $4}' | grep -Eq "(^|:|])${HAVOC_OPERATOR_PORT}$" || {
  echo "Havoc is active but TCP ${HAVOC_OPERATOR_PORT} is not listening." >&2
  exit 1
}
ss -lnt | awk '{print $4}' | grep -Eq "(^|:|])${MYTHIC_HTTPS_PORT}$" || {
  echo "Mythic reports status, but TCP ${MYTHIC_HTTPS_PORT} is not listening." >&2
  exit 1
}

echo
echo "Both C2 cores are installed on ${TEAMSERVER_IP}."
echo "Havoc operator channel : ${TEAMSERVER_IP}:${HAVOC_OPERATOR_PORT}"
echo "Mythic operator UI     : https://${TEAMSERVER_IP}:${MYTHIC_HTTPS_PORT}"
echo 'Training accounts      : operator-01 through operator-99'
echo 'Initial password       : see /etc/deimustech-c2/operator-accounts.txt'
echo 'Havoc profile          : /opt/deimustech/Havoc/profiles/deimustech-lab.yaotl'
echo 'Havoc systemd service  : deimustech-havoc.service (active and enabled)'
echo "Mythic catalog         : $catalog_status"
echo "Lab interface          : $lab_address_status"
echo 'Integrated health check: passed'
echo 'The redirector is not an operator login endpoint; callback/listener routing is configured separately.'
