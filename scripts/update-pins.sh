#!/usr/bin/env bash
# update-pins.sh — 全ソース/アセットをダウンロードしてSHA-256を計算し、
# versions.env の *_SHA256= 行を書き換える。
# バージョン更新時にローカル（WSL2可）で1回実行してコミットする。
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pin() { # pin <versions.envのキー> <URL>
  local key=$1 url=$2 f
  f="$WORK/$(basename "$url")"
  echo ">> $url"
  curl -fL --retry 3 -o "$f" "$url"
  local sum
  sum=$(sha256sum "$f" | cut -d' ' -f1)
  sed -i "s|^${key}=.*|${key}=${sum}|" versions.env
  echo "   ${key}=${sum}"
}

pin GCC_SHA256      "$GCC_URL"
pin BINUTILS_SHA256 "$BINUTILS_URL"
pin AVR_LIBC_SHA256 "$AVR_LIBC_URL"

pin AVRDUDE_SHA256_WINDOWS_X64 "$AVRDUDE_BASE_URL/avrdude-v${AVRDUDE_VERSION}-windows-x64.zip"
pin AVRDUDE_SHA256_LINUX_64BIT "$AVRDUDE_BASE_URL/avrdude_v${AVRDUDE_VERSION}_Linux_64bit.tar.gz"
pin AVRDUDE_SHA256_LINUX_ARM64 "$AVRDUDE_BASE_URL/avrdude_v${AVRDUDE_VERSION}_Linux_ARM64.tar.gz"
pin AVRDUDE_SHA256_MACOS_64BIT "$AVRDUDE_BASE_URL/avrdude_v${AVRDUDE_VERSION}_macOS_64bit.tar.gz"

echo
echo "versions.env updated. Review with: git diff versions.env"
