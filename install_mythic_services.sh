target_kb=$((20 * 1024 * 1024))
safety_kb=$((23 * 1024 * 1024))

repositories=(
  "https://github.com/MythicC2Profiles/httpx"
  "https://github.com/MythicC2Profiles/smb"
  "https://github.com/MythicC2Profiles/tcp"
  "https://github.com/MythicC2Profiles/websocket"
  "https://github.com/MythicC2Profiles/dynamichttp"
  "https://github.com/MythicAgents/Xenon"
  "https://github.com/MythicAgents/freyja"
  "https://github.com/MythicAgents/Athena"
  "https://github.com/MythicC2Profiles/dns"
  "https://github.com/MythicAgents/arachne"
)

for repository in "${repositories[@]}"; do
    available_kb=$(df -Pk / | awk 'NR == 2 {print $4}')

    if (( available_kb < safety_kb )); then
        echo "Stopping with less than 23 GiB available."
        break
    fi

    service=${repository##*/}
    echo "Installing $service..."
    sudo ./mythic-cli install github "$repository"

    available_kb=$(df -Pk / | awk 'NR == 2 {print $4}')
    df -h /

    if (( available_kb < target_kb )); then
        echo "$service crossed the 20 GiB floor; rolling it back."
        sudo ./mythic-cli uninstall "$service"
        sudo ./mythic-cli remove_images
        sudo docker image prune -af
        sudo docker builder prune -af
        break
    fi
done
