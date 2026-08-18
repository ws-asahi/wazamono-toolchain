#!/usr/bin/env bash
# build-avr-gcc.sh — binutils → gcc → avr-libc を所定バージョンでビルドする。
#
# 使い方:
#   scripts/build-avr-gcc.sh native          # 実行ホスト向けネイティブビルド
#   scripts/build-avr-gcc.sh mingw-x64       # Linux上でWindows x64向けカナディアンクロス
#                                            # (事前に native が同一マシンで完了していること)
#
# configureフラグは ZakKemble/avr-gcc-build の既知動作構成に準拠。
# 特に --enable-plugin は必須（欠けると liblto_plugin が生成されず、
# -fno-fat-lto-objects が使えない = Arduinoコアのビルドが通らない）。
# 同理由で LDFLAGS=-static は使用禁止（プラグインの動的ロードと非両立）。
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

MODE=${1:?usage: build-avr-gcc.sh <native|mingw-x64>}
ROOT=$PWD
DL=$ROOT/build/dl
SRC=$ROOT/build/src
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)

case $MODE in
  native)
    HOST_TRIPLET=""                               # configureに--hostを渡さない
    PREFIX=$ROOT/build/prefix-native
    ;;
  mingw-x64)
    HOST_TRIPLET=x86_64-w64-mingw32
    PREFIX=$ROOT/build/prefix-mingw-x64
    NATIVE_PREFIX=$ROOT/build/prefix-native
    [ -x "$NATIVE_PREFIX/bin/avr-gcc" ] || { echo "ERROR: run 'native' first (needs same-version avr-gcc on build host)"; exit 1; }
    export PATH=$NATIVE_PREFIX/bin:$PATH
    ;;
  *) echo "unknown mode: $MODE"; exit 1;;
esac
mkdir -p "$DL" "$SRC" "$PREFIX"

# ---------- fetch & verify ----------
fetch() { # fetch <URL> <SHA256>
  local url=$1 sum=$2 f=$DL/$(basename "$1")
  [ -f "$f" ] || curl -fL --retry 3 -o "$f" "$url"
  if [ -n "$sum" ]; then
    echo "$sum  $f" | sha256sum -c - || { echo "CHECKSUM MISMATCH: $url"; exit 1; }
  else
    echo "WARNING: no pinned checksum for $url (run scripts/update-pins.sh)"
  fi
}
fetch "$BINUTILS_URL" "$BINUTILS_SHA256"
fetch "$GCC_URL"      "$GCC_SHA256"
fetch "$AVR_LIBC_URL" "$AVR_LIBC_SHA256"

extract_once() { # extract_once <tarball> <dirname>
  [ -d "$SRC/$2" ] || tar -xf "$DL/$1" -C "$SRC"
}
extract_once "binutils-${BINUTILS_VERSION}.tar.xz"  "binutils-${BINUTILS_VERSION}"
extract_once "gcc-${GCC_VERSION}.tar.xz"            "gcc-${GCC_VERSION}"
extract_once "avr-libc-${AVR_LIBC_VERSION}.tar.bz2" "avr-libc-${AVR_LIBC_VERSION}"

# gmp/mpfr/mpc をgccソースツリー内に取得（in-treeビルド、カナディアンクロスでも
# host向けに自動でビルドされる）
if [ ! -d "$SRC/gcc-${GCC_VERSION}/gmp" ]; then
  ( cd "$SRC/gcc-${GCC_VERSION}" && ./contrib/download_prerequisites )
fi

# binutilsパッチ適用（patches/binutils/*.patch があれば）
# 0001: bfdio.c マルチバイトパスのセパレータ変換バグ修正（日本語prefix対応に必須）
if compgen -G "patches/binutils/*.patch" > /dev/null; then
  for p in patches/binutils/*.patch; do
    echo ">> applying $p"
    patch -d "$SRC/binutils-${BINUTILS_VERSION}" -p1 -N < "$p" || true
  done
fi

# avr-libcパッチ適用（patches/avr-libc/*.patch があれば。現在は空）
if compgen -G "patches/avr-libc/*.patch" > /dev/null; then
  for p in patches/avr-libc/*.patch; do
    echo ">> applying $p"
    patch -d "$SRC/avr-libc-${AVR_LIBC_VERSION}" -p1 -N < "$p" || true
  done
fi

# ---------- configure args (ZakKemble準拠) ----------
HOST_ARG=()
[ -n "$HOST_TRIPLET" ] && HOST_ARG=(--host="$HOST_TRIPLET")

OPTS_BINUTILS=(
  --target=avr
  --disable-nls
  --disable-werror
)

OPTS_GCC=(
  --target=avr
  --enable-languages=c,c++
  --disable-nls
  --disable-libssp
  --disable-libada
  --with-dwarf2
  --disable-shared
  --enable-static
  --enable-mingw-wildcard
  --enable-plugin
  --with-gnu-as
  --with-gnu-ld
  --without-zstd
  # UTF-8マニフェスト(GCC 13+/PR108865の既定)は有効のまま使う。
  # wazamono1では --disable-win32-utf8-manifest で全ツールをANSI(CP932)に
  # 統一していたが、その理由は「binutils 2.45のbfdio.c多バイトパスバグ +
  # コードページ混在でリンクが壊れる」ことへの回避策だった。現在ピンして
  # いる binutils 2.46.1 で当該バグは上流修正済みのため前提が消滅している。
  # ANSI動作には実害もある: 日本語名フォルダ配下で診断メッセージのパスが
  # CP932バイトで出力され、Arduino IDE⇔arduino-cliのgRPC(UTF-8必須)が
  # "invalid UTF-8" で失敗する。UTF-8マニフェストにより argv/診断とも
  # UTF-8 になりこの問題が根治する。binutils側には同等のconfigure
  # オプションが無いため、下のbinutilsステップでリソースを自前注入して
  # 全ツールのコードページを UTF-8 に統一する。
)

# ---------- 1. binutils ----------
# mingwホスト: binutilsには --enable-win32-utf8-manifest 相当が無いので、
# GCCソース同梱の winnt-utf8.manifest(GCC実行ファイルに入るものと同一)を
# windresでRT_MANIFESTリソースにコンパイルし、LDFLAGS経由で全ホスト実行
# ファイルのリンクに混ぜる。自前のRT_MANIFESTが存在するリンクでは、mingw
# ターゲットのldは default-manifest.o を自動リンクしない(置き換え動作)。
# 埋め込みの成否はスモークテスト(a0)で全数検証する。
BINUTILS_LDFLAGS_ARG=()
if [ -n "$HOST_TRIPLET" ]; then
  MANIFEST_SRC="$SRC/gcc-${GCC_VERSION}/gcc/config/i386/winnt-utf8.manifest"
  [ -f "$MANIFEST_SRC" ] || { echo "FAIL: $MANIFEST_SRC not found"; exit 1; }
  MANIFEST_OBJ="$ROOT/build/utf8-manifest-$MODE.o"
  mkdir -p "$ROOT/build"
  cp "$MANIFEST_SRC" "$ROOT/build/utf8.manifest"
  # 1 = CREATEPROCESS_MANIFEST_RESOURCE_ID, 24 = RT_MANIFEST
  printf '1 24 "utf8.manifest"\n' > "$ROOT/build/utf8-manifest.rc"
  ${HOST_TRIPLET}-windres -I "$ROOT/build" \
    "$ROOT/build/utf8-manifest.rc" "$MANIFEST_OBJ"
  BINUTILS_LDFLAGS_ARG=(LDFLAGS="$MANIFEST_OBJ")
fi

mkdir -p build/obj-binutils-$MODE && cd build/obj-binutils-$MODE
"$SRC/binutils-${BINUTILS_VERSION}/configure" \
  --prefix="$PREFIX" "${HOST_ARG[@]}" "${OPTS_BINUTILS[@]}" \
  "${BINUTILS_LDFLAGS_ARG[@]}"
make -j"$NPROC"
make install
cd "$ROOT"

# nativeビルドでは以降のステップで今作ったbinutilsを使う
[ -z "$HOST_TRIPLET" ] && export PATH=$PREFIX/bin:$PATH

# ---------- 2. gcc (c, c++) ----------
mkdir -p build/obj-gcc-$MODE && cd build/obj-gcc-$MODE
"$SRC/gcc-${GCC_VERSION}/configure" \
  --prefix="$PREFIX" "${HOST_ARG[@]}" "${OPTS_GCC[@]}"
make -j"$NPROC"
make install
cd "$ROOT"

# ---------- 3. avr-libc ----------
if [ -z "$HOST_TRIPLET" ]; then
  # ネイティブ: 今ビルドしたavr-gccでtargetライブラリを構築
  mkdir -p build/obj-avr-libc && cd build/obj-avr-libc
  "$SRC/avr-libc-${AVR_LIBC_VERSION}/configure" \
    --host=avr --prefix="$PREFIX" \
    --build="$("$SRC/avr-libc-${AVR_LIBC_VERSION}/config.guess")"
  make -j"$NPROC"
  make install
  cd "$ROOT"
else
  # カナディアンクロス: avr-libcの成果物(avr/include, avr/lib)はホスト非依存の
  # AVRターゲットバイナリなので、nativeプレフィックスからコピーする
  cp -a "$NATIVE_PREFIX/avr/include" "$PREFIX/avr/"
  cp -a "$NATIVE_PREFIX/avr/lib"     "$PREFIX/avr/"
fi

# ---------- 4. strip host binaries ----------
STRIP=strip
[ -n "$HOST_TRIPLET" ] && STRIP=${HOST_TRIPLET}-strip
find "$PREFIX/bin" "$PREFIX/libexec" -type f \
  \( -perm -u+x -o -name '*.exe' -o -name '*.dll' \) 2>/dev/null | while read -r f; do
  "$STRIP" "$f" 2>/dev/null || true
done

# ---------- 5. smoke test ----------
# (a0) mingwホスト: ホットパスの全実行ファイルにUTF-8マニフェストが
#      入っていること（コードページ混在=wazamono1問題系の再発検知）。
#      gcc系はconfigure既定(PR108865)、binutils系は上の自前注入による。
if [ -n "$HOST_TRIPLET" ]; then
  for exe in "$PREFIX"/bin/avr-gcc.exe \
             "$PREFIX"/bin/avr-g++.exe \
             "$PREFIX"/libexec/gcc/avr/${GCC_VERSION}/cc1.exe \
             "$PREFIX"/libexec/gcc/avr/${GCC_VERSION}/cc1plus.exe \
             "$PREFIX"/bin/avr-as.exe \
             "$PREFIX"/bin/avr-ld.exe \
             "$PREFIX"/bin/avr-objcopy.exe \
             "$PREFIX"/bin/avr-size.exe \
             "$PREFIX"/bin/avr-nm.exe; do
    [ -f "$exe" ] || { echo "FAIL: $exe missing"; exit 1; }
    if ! grep -q activeCodePage "$exe"; then
      echo "FAIL: UTF-8 manifest missing in $(basename "$exe")"
      exit 1
    fi
  done
  echo "OK: UTF-8 manifest present in all hot-path host executables"
fi

# (a) LTOリンカプラグインの存在（欠けると -fno-fat-lto-objects が使えない）
PLUGIN=$(find "$PREFIX/libexec/gcc/avr/${GCC_VERSION}" -name 'liblto_plugin*' | head -1)
[ -n "$PLUGIN" ] || { echo "FAIL: liblto_plugin not found (LTO linker plugin missing)"; exit 1; }
echo "OK: LTO plugin ($PLUGIN)"

# (b) DU対応の核心確認: device-specs / crt / libdevice が揃っているか
for mcu in avr64du32 avr32du20; do
  specs=$(find "$PREFIX" -name "specs-$mcu" | head -1)
  [ -n "$specs" ] || { echo "FAIL: device-specs specs-$mcu not found"; exit 1; }
  crt=$(find "$PREFIX/avr/lib" -name "crt$mcu.o" | head -1)
  [ -n "$crt" ]   || { echo "FAIL: crt$mcu.o not found (avr-libc DU support missing)"; exit 1; }
  echo "OK: $mcu ($specs / $crt)"
done

if [ -z "$HOST_TRIPLET" ]; then
  # (c) 実リンクテスト + LTO/プラグイン経路の実動作確認
  T=$(mktemp -d)
  echo 'int main(void){return 0;}' > "$T/t.c"
  for mcu in avr64du32 avr32du20; do
    "$PREFIX/bin/avr-gcc" -mmcu=$mcu -Os "$T/t.c" -o "$T/t-$mcu.elf"
    "$PREFIX/bin/avr-gcc" -mmcu=$mcu -Os -flto -fno-fat-lto-objects \
      "$T/t.c" -o "$T/t-$mcu-lto.elf"
    "$PREFIX/bin/avr-size" "$T/t-$mcu.elf"
    echo "OK: link test $mcu (plain + LTO slim)"
  done
  rm -rf "$T"
  "$PREFIX/bin/avr-gcc" --version | head -1
fi

echo "DONE: $MODE -> $PREFIX"
