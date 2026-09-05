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
| x86_64-apple-darwin | 自前ビルド | 公式 macOS_64bit | Phase 2 |
| arm64-apple-darwin | 自前ビルド | 公式 macOS_64bit（Rosetta 2） | Phase 2 |

Windows ARM64 はボードマネージャーが x86_64-mingw32 を選択し x64 エミュレーションで動作。
