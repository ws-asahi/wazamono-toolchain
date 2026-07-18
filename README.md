# wazamono-toolchain

WazamonoCore（Arduinoボードマネージャー配布）用ツールチェーンのビルド・パッケージングリポジトリ。

生成物は2系統：

1. **avr-gcc** — GCC + binutils + avr-libc をソースから自前ビルド（AVR DUシリーズ完全対応）
2. **avrdude** — avrdudes/avrdude 公式リリースバイナリ（無改変）を統一レイアウトへ正規化再パッケージ

## リリース手順

```
1. versions.env を更新（バージョン変更時は必ず PKG_REV を進める）
2. scripts/update-pins.sh を実行して SHA-256 ピンを更新、コミット
3. git tag tools-<GCC_VERSION>-<PKG_REV> && git push --tags
4. Actions 完了後、Draft Release の内容を確認して公開
5. Release添付の tools-fragment.json を
   package_ws-asahi_wazamono_index.json の tools セクションへ転記
```

## 統一レイアウト規約

| ツール | アーカイブ内トップ | platform.txt 参照 |
|---|---|---|
| avr-gcc | `avr-gcc-<ver>-<rev>/bin/...` | `compiler.path={runtime.tools.avr-gcc.path}/bin/` |
| avrdude | `avrdude-<ver>-<rev>/bin/avrdude`, `etc/avrdude.conf` | `{runtime.tools.avrdude.path}/bin/avrdude` `-C.../etc/avrdude.conf` |

全ホストtar.gz統一・実行ビット付与済み・最上位フォルダ1階層。

## 運用ルール

- **同一 name+version のアーカイブ差し替え禁止**（インストール済みユーザーに反映されないため、中身を変えたら PKG_REV を進める）
- avrdude公式アセットはSHA-256でピン留めし、上流の黙った差し替えをCIで検知する
- avr-libc は最新リリース追従。上流未収録の修正を先行させる場合は
  `patches/avr-libc/*.patch`（`git format-patch` 形式）を置けばビルド時に自動適用される
- **既知の経過措置**: avr-libc 2.3.2 のモダンAVR向け `<avr/wdt.h>` には
  WDT修正（avr-libc #1068/#1069、マージ済み・未リリース）が入っていない。
  2.3.3/2.4.0 リリースで解消予定。一般リリースまでに上流リリースが無い場合は
  WazamonoCore 側に wdt_compat.h を復活させること

## ホストカバレッジ

| host | avr-gcc | avrdude | 状態 |
|---|---|---|---|
| x86_64-mingw32 | 自前ビルド（カナディアンクロス） | 公式 windows-x64 (MSVC) | Phase 1 |
| x86_64-pc-linux-gnu | 自前ビルド（ネイティブ） | 公式 Linux_64bit | Phase 1 |
| aarch64-linux-gnu | 自前ビルド | 公式 Linux_ARM64 | Phase 2 |
| x86_64-apple-darwin | 自前ビルド | 公式 macOS_64bit | Phase 2 |
| arm64-apple-darwin | 自前ビルド | 公式 macOS_64bit（Rosetta 2） | Phase 2 |

Windows ARM64 はボードマネージャーが x86_64-mingw32 を選択し x64 エミュレーションで動作。
