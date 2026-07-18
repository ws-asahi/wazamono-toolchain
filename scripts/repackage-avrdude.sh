#!/usr/bin/env bash
# repackage-avrdude.sh — avrdudes/avrdude 公式リリースバイナリ（無改変）を
# 全ホスト統一レイアウトに再パッケージする。
#
# 統一レイアウト:
#   avrdude-<ver>-<rev>/
#   ├── bin/avrdude(.exe)      (実行ビット付与済み)
#   └── etc/avrdude.conf
#
# platform.txt側（全OS共通・OS分岐不要）:
#   tools.avrdude.cmd={runtime.tools.avrdude.path}/bin/avrdude
#   -C{runtime.tools.avrdude.path}/etc/avrdude.conf
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

TOOLVER="${AVRDUDE_VERSION}-${PKG_REV}"
TOP="avrdude-${TOOLVER}"
OUT=dist
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# アセット名 / Arduinoホスト文字列 / ピンキー の対応表
# 形式: <公式アセット名>|<host文字列(複数は空白区切り)>|<SHA256変数名>
# macOSはx86_64バイナリ1本のみ提供 → arm64はRosetta 2実行前提で同一アーカイブを
# 両hostに割り当てる（gen-index-fragment.py側でhostごとにエントリ化）
ASSETS=(
  "avrdude-v${AVRDUDE_VERSION}-windows-x64.zip|x86_64-mingw32|AVRDUDE_SHA256_WINDOWS_X64"
  "avrdude_v${AVRDUDE_VERSION}_Linux_64bit.tar.gz|x86_64-pc-linux-gnu|AVRDUDE_SHA256_LINUX_64BIT"
  "avrdude_v${AVRDUDE_VERSION}_Linux_ARM64.tar.gz|aarch64-linux-gnu|AVRDUDE_SHA256_LINUX_ARM64"
  "avrdude_v${AVRDUDE_VERSION}_macOS_64bit.tar.gz|x86_64-apple-darwin arm64-apple-darwin|AVRDUDE_SHA256_MACOS_64BIT"
)

for entry in "${ASSETS[@]}"; do
  IFS='|' read -r asset hosts sumvar <<< "$entry"
  url="$AVRDUDE_BASE_URL/$asset"
  f="$WORK/$asset"
  echo ">> $url"
  curl -fL --retry 3 -o "$f" "$url"

  pinned=${!sumvar:-}
  if [ -n "$pinned" ]; then
    echo "$pinned  $f" | sha256sum -c - || { echo "UPSTREAM ASSET CHANGED: $asset"; exit 1; }
  else
    echo "WARNING: no pin for $asset (run scripts/update-pins.sh)"
  fi

  # 展開（内部レイアウトはアセットごとに異なるため、実行ファイルとconfを探して拾う）
  x="$WORK/x-$asset"; mkdir -p "$x"
  case $asset in
    *.zip)    unzip -q "$f" -d "$x" ;;
    *.tar.gz) tar -xzf "$f" -C "$x" ;;
  esac

  bin=$(find "$x" -type f \( -name avrdude -o -name avrdude.exe \) | head -1)
  conf=$(find "$x" -type f -name avrdude.conf | head -1)
  [ -n "$bin" ]  || { echo "FAIL: avrdude binary not found in $asset"; find "$x" -type f; exit 1; }
  [ -n "$conf" ] || { echo "FAIL: avrdude.conf not found in $asset"; find "$x" -type f; exit 1; }

  # DUパーツ定義の存在確認（8.1標準confに収録済みであることの検証）
  grep -q "AVR64DU32" "$conf" || { echo "FAIL: avrdude.conf lacks AVR64DU32 part"; exit 1; }

  stage="$WORK/stage-$asset/$TOP"
  mkdir -p "$stage/bin" "$stage/etc"
  cp "$bin"  "$stage/bin/$(basename "$bin")"
  cp "$conf" "$stage/etc/avrdude.conf"
  chmod +x "$stage/bin/"*

  for host in $hosts; do
    archive="$OUT/avrdude-${TOOLVER}-${host}.tar.gz"
    tar -C "$WORK/stage-$asset" -czf "$archive" "$TOP"
    sha256sum "$archive"
  done
done

echo "DONE. dist/:"
ls -la "$OUT"/avrdude-*
