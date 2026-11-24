#!/usr/bin/env bash
# OpenCruise アプリの更新ファイル(.ocapp)を作る。ふつうは scripts/build-os.sh --app-update から呼ばれる。
#   scripts/make-app-update.sh <インストール先のフォルダ> <出力フォルダ> [変更内容のメモ]
#     インストール先: bitbake opencruise の image(usr/bin/opencruise と usr/share/opencruise がある所)
#
# .ocapp の中身(ただの tar。圧縮しない):
#   manifest.json    { "format": 1, "build": "<ビルド番号 YYYYMMDDhhmmss>", "version": "0.1.0", "created": "...",
#                      "payload": "payload.tar.gz", "payloadSize": <バイト>, "payloadSha256": "...", "notes": "..." }
#   payload.tar.gz   usr/bin/opencruise と usr/share/opencruise/(フォント・効果音・build-id)
# 車のアプリ(UpdateManager)は manifest を読み、payload の sha256 を確かめてから /home/opencruise/app/versions/<build>/ に展開する。
# 出力フォルダの index.json(ネット経由の更新で最初に読むもの)も、いちばん新しい .ocapp に合わせて作り直す。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
img="${1:?インストール先のフォルダを指定してください}"
out="${2:?出力フォルダを指定してください}"
notes="${3:-}"

[ -x "$img/usr/bin/opencruise" ] || { echo "エラー: $img/usr/bin/opencruise がありません" >&2; exit 1; }
build="$(cat "$img/usr/share/opencruise/build-id" 2>/dev/null || date -u +%Y%m%d%H%M%S)"
version="$(sed -n 's/^project(OpenCruise VERSION \([0-9.]*\).*/\1/p' "$REPO/CMakeLists.txt" 2>/dev/null | head -n 1 || true)"
if [ -z "$notes" ]; then
    notes="$(git -C "$REPO" log -1 --format='%h %s' 2>/dev/null || true)"
    git -C "$REPO" diff --quiet 2>/dev/null || notes="$notes(+ コミットしていない変更)"
fi

mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -C "$img" -czf "$tmp/payload.tar.gz" usr/bin/opencruise usr/share/opencruise
sum="$(sha256sum "$tmp/payload.tar.gz" | cut -d' ' -f1)"
size="$(stat -c %s "$tmp/payload.tar.gz")"
python3 - "$tmp/manifest.json" "$build" "${version:-0.0.0}" "$size" "$sum" "$notes" <<'PY'
import json, sys, datetime
path, build, version, size, sha, notes = sys.argv[1:]
json.dump({"format": 1, "build": build, "version": version,
           "created": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
           "payload": "payload.tar.gz", "payloadSize": int(size), "payloadSha256": sha, "notes": notes},
          open(path, "w"), ensure_ascii=False, indent=2)
PY
file="opencruise-app-$build.ocapp"
tar -C "$tmp" -cf "$out/$file" manifest.json payload.tar.gz
echo "作りました: $out/$file(ビルド $build、$(du -h "$out/$file" | cut -f1))"
bash "$HERE/update-server.sh" --index-only "$out"
