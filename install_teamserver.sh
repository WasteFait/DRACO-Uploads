#!/usr/bin/env bash
# Single entry point for the DeimusTech combined Havoc/Mythic teamserver.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lab.env"

if [[ ${EUID} -eq 0 ]]; then
  echo 'Run as a sudo-capable user, not root.' >&2
  exit 1
fi
if ! ip -4 -o addr show | awk '{print $4}' | grep -qx "${TEAMSERVER_IP}/${TEAMSERVER_PREFIX}"; then
  echo "This host does not own ${TEAMSERVER_IP}/${TEAMSERVER_PREFIX}. Configure its management NIC first." >&2
  exit 1
fi

export DEIMUSTECH_OFFLINE_BUNDLE=${DEIMUSTECH_OFFLINE_BUNDLE:-}
"$script_dir/install_havoc_teamserver_ubuntu.sh"
"$script_dir/install_mythic_server_ubuntu.sh"

sudo install -d -m 0750 -o "$USER" -g "$USER" /etc/deimustech-c2
sudo install -m 0644 "$script_dir/lab.env" /etc/deimustech-c2/lab.env
cd /opt/deimustech/Mythic
sudo ./mythic-cli start
cd "$script_dir"
./provision_default_operators.py

echo
echo "Both C2 cores are installed on ${TEAMSERVER_IP}."
echo "Havoc operator channel : ${TEAMSERVER_IP}:${HAVOC_OPERATOR_PORT}"
echo "Mythic operator UI     : https://${TEAMSERVER_IP}:${MYTHIC_HTTPS_PORT}"
echo 'Training accounts      : operator-01 through operator-99'
echo 'Initial password       : see /etc/deimustech-c2/operator-accounts.txt'
echo 'Havoc profile          : /opt/deimustech/Havoc/profiles/deimustech-lab.yaotl'
echo 'The redirector is not an operator login endpoint; callback/listener routing is configured separately.'
