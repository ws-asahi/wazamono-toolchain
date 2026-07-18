#!/usr/bin/env bash
# package-avr-gcc.sh — インストールツリーをボードマネージャー配布用tar.gzにする。
#
# 使い方:
#   scripts/package-avr-gcc.sh build/prefix-native    x86_64-pc-linux-gnu
#   scripts/package-avr-gcc.sh build/prefix-mingw-x64 x86_64-mingw32
#
# アーカイブ規約:
#   - 最上位フォルダ1階層（IDEが展開時に剥がす）: avr-gcc-<ver>-<rev>/
#   - platform.txt側は compiler.path={runtime.tools.avr-gcc.path}/bin/ で解決
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

PREFIX=${1:?usage: package-avr-gcc.sh <prefix-dir> <arduino-host-string>}
HOST=${2:?}
TOOLVER="${GCC_VERSION}-${PKG_REV}"
TOP="avr-gcc-${TOOLVER}"
OUT=dist
mkdir -p "$OUT"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -a "$PREFIX" "$STAGE/$TOP"

# 配布に不要なものを削る（サイズ削減）
rm -rf "$STAGE/$TOP/share/info" "$STAGE/$TOP/share/man" "$STAGE/$TOP/share/doc" || true

ARCHIVE="$OUT/avr-gcc-${TOOLVER}-${HOST}.tar.gz"
tar -C "$STAGE" -czf "$ARCHIVE" "$TOP"

sha256sum "$ARCHIVE"
stat -c '%n %s bytes' "$ARCHIVE" 2>/dev/null || stat -f '%N %z bytes' "$ARCHIVE"
