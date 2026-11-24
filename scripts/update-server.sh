#!/usr/bin/env bash
# アプリの更新ファイル(.ocapp)を、同じ LAN の車へネット経由で配る(設定 > システム > アップデート の「ネットで確認」)。
#   scripts/update-server.sh [フォルダ(既定: ~/opencruise-yocto/updates)] [ポート(既定: 8765)]
#   scripts/update-server.sh --index-only <フォルダ>   index.json を作り直すだけ(make-app-update.sh が使う)
# 車のアプリは http://opencruise-dev.local:8765/index.json を読む(アプリの定数。変えるときは app/src/system/UpdateManager.h)。
#   → この PC のホスト名を opencruise-dev にして、mDNS(Linux は avahi-daemon、Windows 10 以降は標準)で名前が見えるようにする。
#   → QEMU などの仮想マシンの中で動かすときは、ポートを外へ転送する(例: -netdev user,...,hostfwd=tcp::8765-:8765)。
#     その場合、名前(opencruise-dev.local)は仮想マシンではなく、外側の PC(Windows など)のホスト名になる。
# index.json: { "app": { "build", "version", "file", "size", "sha256"(.ocapp 全体), "notes" } }(いちばん新しいビルド)
set -euo pipefail
index_only=0
[ "${1:-}" = "--index-only" ] && { index_only=1; shift; }
dir="${1:-$HOME/opencruise-yocto/updates}"
port="${2:-8765}"
[ -d "$dir" ] || { echo "エラー: フォルダがありません: $dir(先に scripts/build-os.sh --app-update)" >&2; exit 1; }

python3 - "$dir" <<'PY'
import json, sys, os, glob, hashlib, tarfile
d = sys.argv[1]
files = sorted(glob.glob(os.path.join(d, "opencruise-app-*.ocapp")))
best = None
for f in files:
    try:
        with tarfile.open(f) as t:
            m = json.load(t.extractfile("manifest.json"))
    except Exception as e:
        print("読めない更新ファイル:", f, e); continue
    if best is None or m.get("build", "") > best[1].get("build", ""):
        best = (f, m)
index = {}
if best:
    f, m = best
    h = hashlib.sha256()
    with open(f, "rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""): h.update(chunk)
    index["app"] = {"build": m.get("build"), "version": m.get("version"), "file": os.path.basename(f),
                    "size": os.path.getsize(f), "sha256": h.hexdigest(), "notes": m.get("notes", "")}
json.dump(index, open(os.path.join(d, "index.json"), "w"), ensure_ascii=False, indent=2)
print("index.json:", index.get("app", {}).get("file", "(更新ファイルなし)"))
PY
[ "$index_only" -eq 1 ] && exit 0

echo "配っています: http://$(hostname).local:$port/  (フォルダ: $dir、止めるときは Ctrl+C)"
[ "$(hostname)" = opencruise-dev ] || echo "注意: ホスト名が opencruise-dev ではありません。車からは http://opencruise-dev.local:$port を探します"
exec python3 -m http.server "$port" --directory "$dir"
