#!/usr/bin/env bash
# package-avr-gcc.sh — インストールツリーをボードマネージャー配布用tar.gzにする。
#
# 使い方:
#   scripts/package-avr-gcc.sh build/prefix-native    x86_64-pc-linux-gnu
#   scripts/package-avr-gcc.sh build/prefix-mingw-x64 x86_64-mingw32
#   scripts/package-avr-gcc.sh build/prefix-native    arm64-apple-darwin   # macOS ランナー上
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

# macOS: 標準の bsdtar は拡張属性/リソースフォークを AppleDouble(._*) や
# pax ヘッダとしてアーカイブに混入させる。GNU tar(ランナーには gtar として
# 同梱)があればそれを使い、無い場合も COPYFILE_DISABLE で混入を止める。
export COPYFILE_DISABLE=1
TAR=tar
command -v gtar >/dev/null 2>&1 && TAR=gtar

sha256_print() { # sha256_print <file>
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi
}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -a "$PREFIX" "$STAGE/$TOP"

# 配布に不要なものを削る（サイズ削減）
rm -rf "$STAGE/$TOP/share/info" "$STAGE/$TOP/share/man" "$STAGE/$TOP/share/doc" || true

ARCHIVE="$OUT/avr-gcc-${TOOLVER}-${HOST}.tar.gz"
"$TAR" -C "$STAGE" -czf "$ARCHIVE" "$TOP"

# AppleDouble 混入の全数検証(macOS 以外では常に空)
if "$TAR" -tzf "$ARCHIVE" | grep -q '/\._'; then
  echo "FAIL: AppleDouble (._*) entries found in $ARCHIVE"; exit 1
fi

sha256_print "$ARCHIVE"
stat -c '%n %s bytes' "$ARCHIVE" 2>/dev/null || stat -f '%N %z bytes' "$ARCHIVE"
