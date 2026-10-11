#!/usr/bin/env bash
# Install the pinned official-community catalog of Mythic agents and C2 profiles.
set -euo pipefail
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a sudo-capable user, not root.' >&2; exit 1; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
manifest="$script_dir/mythic_catalog.tsv"
mythic_dir=/opt/deimustech/Mythic
state_dir=/var/lib/deimustech-c2
log_dir=/var/log/deimustech-c2
success_file=$state_dir/mythic-catalog-success.tsv
failure_file=$state_dir/mythic-catalog-failures.tsv

[[ -x $mythic_dir/mythic-cli ]] || { echo "Missing $mythic_dir/mythic-cli" >&2; exit 1; }
[[ -f $manifest ]] || { echo "Missing catalog manifest: $manifest" >&2; exit 1; }
[[ -z ${DEIMUSTECH_OFFLINE_BUNDLE:-} ]] || {
  echo 'The full catalog installer requires temporary Internet access; the base offline bundle does not contain these 50 repositories and images.' >&2
  exit 1
}

available_kib=$(df --output=avail "$mythic_dir" | awk 'NR==2 {print $1}')
if [[ ! $available_kib =~ ^[0-9]+$ ]] || ((available_kib < 20 * 1024 * 1024)); then
  echo 'At least 20 GiB of free disk is required before attempting the full Mythic catalog.' >&2
  exit 1
fi

sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" "$state_dir" "$log_dir"
touch "$success_file"
chmod 0600 "$success_file"
: > "$failure_file"
chmod 0600 "$failure_file"
log_file="$log_dir/mythic-catalog-$(date +%Y%m%d-%H%M%S).log"
touch "$log_file"
chmod 0600 "$log_file"

total=$(awk -F '\t' '!/^#/ && NF==2 {n++} END {print n+0}' "$manifest")
completed=0
failed=0
index=0
cd "$mythic_dir"
while IFS=$'\t' read -r category repository; do
  [[ -z ${category:-} || $category == \#* ]] && continue
  index=$((index + 1))
  if [[ ${DEIMUSTECH_REFRESH_MYTHIC_CATALOG:-0} != 1 ]] && grep -Fqx "$category"$'\t'"$repository" "$success_file"; then
    echo "[$index/$total] already installed: $repository" | tee -a "$log_file"
    completed=$((completed + 1))
    continue
  fi
  echo "[$index/$total] installing $category: $repository" | tee -a "$log_file"
  if sudo ./mythic-cli install github "$repository" --force 2>&1 | tee -a "$log_file"; then
    grep -Fvx "$category"$'\t'"$repository" "$success_file" > "${success_file}.tmp" || true
    mv "${success_file}.tmp" "$success_file"
    printf '%s\t%s\n' "$category" "$repository" >> "$success_file"
    chmod 0600 "$success_file"
    completed=$((completed + 1))
  else
    printf '%s\t%s\n' "$category" "$repository" | tee -a "$failure_file" "$log_file" >/dev/null
    failed=$((failed + 1))
  fi
done < "$manifest"

sudo ./mythic-cli start 2>&1 | tee -a "$log_file"
sudo ./mythic-cli status 2>&1 | tee -a "$log_file"
echo "Mythic catalog result: $completed installed/previously complete, $failed failed, $total catalog entries."
echo "Log: $log_file"
if ((failed)); then
  echo "Failures: $failure_file" >&2
  exit 1
fi
