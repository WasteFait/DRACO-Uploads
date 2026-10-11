#!/usr/bin/env bash
# Single entry point for an Ubuntu Desktop student workstation gold image.
set -euo pipefail
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a sudo-capable user, not root.' >&2; exit 1; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl firefox network-manager open-vm-tools open-vm-tools-desktop

"$script_dir/install_havoc_client_ubuntu.sh"

sudo install -d -m 0755 /usr/local/lib/deimustech /var/lib/deimustech
sudo install -m 0755 "$script_dir/student_clone_firstboot.sh" \
  /usr/local/lib/deimustech/student-clone-firstboot

sudo tee /etc/systemd/system/deimustech-clone-personalize.service >/dev/null <<'EOF'
[Unit]
Description=DeimusTech operator clone hostname personalization
Wants=network-online.target
After=network-online.target NetworkManager-wait-online.service
ConditionPathExists=!/var/lib/deimustech/operator-clone-personalized

[Service]
Type=oneshot
ExecStart=/usr/local/lib/deimustech/student-clone-firstboot
TimeoutStartSec=135

[Install]
WantedBy=multi-user.target
EOF

sudo tee /usr/share/applications/deimustech-havoc.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=DeimusTech Havoc Operator
Comment=Connect to the DeimusTech teamserver
Exec=/opt/deimustech/Havoc/havoc client
Terminal=false
Categories=Network;Security;
EOF

sudo tee /usr/share/applications/deimustech-mythic.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=DeimusTech Mythic Console
Comment=Open the DeimusTech Mythic operator console
Exec=firefox --new-window https://172.16.113.66:7443
Terminal=false
Categories=Network;Security;
EOF

sudo chmod 0644 /usr/share/applications/deimustech-havoc.desktop \
  /usr/share/applications/deimustech-mythic.desktop
sudo systemctl daemon-reload
sudo systemctl enable NetworkManager-wait-online.service deimustech-clone-personalize.service

echo
echo 'Student gold image installation is complete.'
echo 'IMPORTANT: shut down and convert this VM to a template without booting it again.'
echo 'Each clone must receive exactly one address from 172.16.113.101-199.'
echo 'At first boot, that address becomes hostname ops-01 through ops-99.'
