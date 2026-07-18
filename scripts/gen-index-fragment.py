#!/usr/bin/env python3
"""gen-index-fragment.py — dist/ のアーカイブ群から package_*_index.json の
"tools" セクション断片を機械生成する（checksum手動転記ミスの排除）。

使い方:
    python3 scripts/gen-index-fragment.py \
        --url-base https://github.com/ws-asahi/wazamono-toolchain/releases/download/<tag> \
        > dist/tools-fragment.json

出力を package_ws-asahi_wazamono_index.json の packages[0].tools に貼り込み、
プラットフォーム側は toolsDependencies で
  { "packager": "WazamonoCore", "name": "avr-gcc",  "version": "<GCC_VERSION>-<PKG_REV>" }
  { "packager": "WazamonoCore", "name": "avrdude",  "version": "<AVRDUDE_VERSION>-<PKG_REV>" }
を参照する。
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

# アーカイブ名: <tool>-<version>-<host>.tar.gz
# host はArduinoの正規host文字列（ハイフンを含む）なので既知集合で照合する
KNOWN_HOSTS = [
    "x86_64-mingw32",
    "i686-mingw32",
    "x86_64-pc-linux-gnu",
    "aarch64-linux-gnu",
    "arm-linux-gnueabihf",
    "x86_64-apple-darwin",
    "arm64-apple-darwin",
]

def parse_name(fname: str):
    m = None
    for host in KNOWN_HOSTS:
        if fname.endswith(f"-{host}.tar.gz"):
            stem = fname[: -len(f"-{host}.tar.gz")]
            m = (stem, host)
            break
    if not m:
        return None
    stem, host = m
    # stem = <tool>-<version>  (version は数字始まり)
    mm = re.match(r"^(.+?)-(\d.*)$", stem)
    if not mm:
        return None
    return mm.group(1), mm.group(2), host

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dist", default="dist")
    ap.add_argument("--url-base", required=True,
                    help="Release download URL base (no trailing slash)")
    args = ap.parse_args()

    tools = {}  # (name, version) -> systems[]
    for f in sorted(Path(args.dist).glob("*.tar.gz")):
        parsed = parse_name(f.name)
        if not parsed:
            print(f"skip (unrecognized): {f.name}", file=sys.stderr)
            continue
        name, version, host = parsed
        sha = hashlib.sha256(f.read_bytes()).hexdigest()
        tools.setdefault((name, version), []).append({
            "host": host,
            "url": f"{args.url_base}/{f.name}",
            "archiveFileName": f.name,
            "checksum": f"SHA-256:{sha}",
            "size": str(f.stat().st_size),
        })

    fragment = [
        {"name": name, "version": version, "systems": systems}
        for (name, version), systems in sorted(tools.items())
    ]
    json.dump(fragment, sys.stdout, indent=2, ensure_ascii=False)
    print()

if __name__ == "__main__":
    main()
