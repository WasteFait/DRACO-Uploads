#!/usr/bin/env bash
# Ensure Havoc receives a Go release new enough to understand standard io/fs.
set -euo pipefail
go_version=1.22.12
minimum_minor=18

version_is_usable() {
  command -v go >/dev/null 2>&1 || return 1
  local raw major minor
  raw=$(go env GOVERSION 2>/dev/null || go version | awk '{print $3}')
  raw=${raw#go}
  major=${raw%%.*}
  minor=${raw#*.}; minor=${minor%%.*}
  [[ $major =~ ^[0-9]+$ && $minor =~ ^[0-9]+$ ]] || return 1
  ((major > 1 || (major == 1 && minor >= minimum_minor)))
}

if version_is_usable; then
  echo "Compatible Go already installed: $(go version)"
  exit 0
fi

case $(uname -m) in
  x86_64|amd64)
    go_arch=amd64
    go_sha=4fa4f869b0f7fc6bb1eb2660e74657fbf04cdd290b5aef905585c86051b34d43
    ;;
  aarch64|arm64)
    go_arch=arm64
    go_sha=fd017e647ec28525e86ae8203236e0653242722a7436929b1f775744e26278e7
    ;;
  *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
esac

archive="go${go_version}.linux-${go_arch}.tar.gz"
offline=${DEIMUSTECH_OFFLINE_BUNDLE:-}
if [[ -n $offline ]]; then
  source_archive="$offline/toolchains/$archive"
  [[ -f $source_archive ]] || { echo "Offline bundle is missing toolchains/$archive" >&2; exit 1; }
else
  download_dir=$(mktemp -d /tmp/deimustech-go.XXXXXX)
  source_archive="$download_dir/$archive"
  curl -fL "https://go.dev/dl/$archive" -o "$source_archive"
fi

printf '%s  %s\n' "$go_sha" "$source_archive" | sha256sum -c -
install_root="/opt/deimustech/toolchains/go${go_version}"
sudo install -d -m 0755 "$install_root"
sudo tar -C "$install_root" --strip-components=1 -xzf "$source_archive"
sudo ln -sfn "$install_root/bin/go" /usr/local/bin/go
sudo ln -sfn "$install_root/bin/gofmt" /usr/local/bin/gofmt
hash -r
version_is_usable || { echo 'Compatible Go installation failed.' >&2; exit 1; }
echo "Installed compatible toolchain: $(go version)"
