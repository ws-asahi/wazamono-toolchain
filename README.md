# wazamono-toolchain

WazamonoCore（Arduinoボードマネージャー配布）用ツールチェーンのビルド・パッケージングリポジトリ。

生成物は2系統：

1. **avr-gcc** — GCC + binutils + avr-libc をソースから自前ビルド（AVR DUシリーズ完全対応）
2. **avrdude** — avrdudes/avrdude 公式リリースバイナリ（無改変）を統一レイアウトへ正規化再パッケージ

## 統一レイアウト規約

| ツール | アーカイブ内トップ | platform.txt 参照 |
|---|---|---|
| avr-gcc | `avr-gcc-<ver>-<rev>/bin/...` | `compiler.path={runtime.tools.avr-gcc.path}/bin/` |
| avrdude | `avrdude-<ver>-<rev>/bin/avrdude`, `etc/avrdude.conf` | `{runtime.tools.avrdude.path}/bin/avrdude` `-C.../etc/avrdude.conf` |

全ホストtar.gz統一・実行ビット付与済み・最上位フォルダ1階層。

## ホストカバレッジ

| host | avr-gcc | avrdude | 状態 |
|---|---|---|---|
| x86_64-mingw32 | 自前ビルド（カナディアンクロス） | 公式 windows-x64 (MSVC) | Phase 1 |
| x86_64-pc-linux-gnu | 自前ビルド（ネイティブ） | 公式 Linux_64bit | Phase 1 |
| aarch64-linux-gnu | 自前ビルド | 公式 Linux_ARM64 | Phase 2 |
| x86_64-apple-darwin | 自前ビルド（ネイティブ, macos-15-intel） | 公式 macOS_64bit | release-macos.yml |
| arm64-apple-darwin | 自前ビルド（ネイティブ, macos-15） | 公式 macOS_64bit（Rosetta 2） | release-macos.yml |

Windows ARM64 はボードマネージャーが x86_64-mingw32 を選択し x64 エミュレーションで動作。

## macOS 版の追加手順（既存リリースへの追記）

Linux/Windows 版を公開済みのリリースに macOS 版 avr-gcc を後から足す場合は、
`release.yml` を再実行せず（チェックサムが変わり配布済みインデックスと食い違う）、
`release-macos.yml` を手動実行する。

1. Actions → **release-macos** → Run workflow。`release_tag` に追加先の既存タグ
   （例: `tools-15.2.0-wazamono2`）を指定。`versions.env` から導かれるタグ名と
   一致しない場合はビルド前に失敗する。
2. 完了するとリリースに `avr-gcc-<ver>-<rev>-{x86_64,arm64}-apple-darwin.tar.gz` と
   `checksums-darwin.txt` / `tools-fragment-darwin.json` が追加される
   （既存アセットは上書きしない）。
3. `tools-fragment-darwin.json` の `systems` 2件を、各コアのパッケージインデックス
   （`package_*_index.json`）の `tools[avr-gcc].systems` に追記する。
   プラットフォーム側の `toolsDependencies` は変更不要（同じ name/version のため）。
   インデックスを GitHub Pages に反映すれば、コアの新バージョンを出さなくても
   macOS のボードマネージャーに表示されるようになる。

macOS ビルドの要点（`scripts/build-avr-gcc.sh` の `IS_DARWIN` 分岐）:
- macOS 標準 Bash 3.2 対応（空配列の `set -u` 安全な展開）
- binutils に `--without-zstd`（Homebrew の libzstd への動的依存を排除）
- `MACOSX_DEPLOYMENT_TARGET`（x86_64: 10.15 / arm64: 11.0）で下位 macOS 互換
- `strip -x` 後に全 Mach-O を ad-hoc 再署名（Apple Silicon で未署名は起動不可）
- スモークテストで Homebrew 依存なし・署名有効・最小 OS バージョンを全数検証
