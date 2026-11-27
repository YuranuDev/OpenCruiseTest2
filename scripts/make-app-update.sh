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
# どのソースからビルドしたか: レシピ(opencruise_git.bb)が do_install で書く source-info(source=github|local, commit, branch, subject, dirty)。
# ここで手元のリポジトリの git を見てはいけない(「GitHub の main」でビルドしたときは、手元の HEAD と別のコミットがビルドされるため)
srcinfo="$img/usr/share/opencruise/source-info"
si() { sed -n "s/^$1=//p" "$srcinfo" 2>/dev/null | head -n 1; }
src_text=""
if [ -f "$srcinfo" ]; then
    commit7="$(si commit | cut -c1-7)"
    if [ "$(si source)" = github ]; then
        src_text="GitHub $(si branch) ${commit7}"
    else
        src_text="手元のフォルダ $(si branch) ${commit7}"
        [ "$(si dirty)" = yes ] && src_text="$src_text(+ コミットしていない変更)"
    fi
fi
if [ -z "$notes" ]; then
    if [ -n "$src_text" ]; then
        notes="$src_text: $(si subject)"
    else
        # 古いビルド(source-info がない)だけ、従来どおり手元のリポジトリから
        notes="$(git -C "$REPO" log -1 --format='%h %s' 2>/dev/null || true)"
        git -C "$REPO" diff --quiet 2>/dev/null || notes="$notes(+ コミットしていない変更)"
    fi
fi

mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -C "$img" -czf "$tmp/payload.tar.gz" usr/bin/opencruise usr/share/opencruise
sum="$(sha256sum "$tmp/payload.tar.gz" | cut -d' ' -f1)"
size="$(stat -c %s "$tmp/payload.tar.gz")"
python3 - "$tmp/manifest.json" "$build" "${version:-0.0.0}" "$size" "$sum" "$notes" "$srcinfo" <<'PY'
import json, sys, datetime, os
path, build, version, size, sha, notes, srcinfo = sys.argv[1:]
m = {"format": 1, "build": build, "version": version,
     "created": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
     "payload": "payload.tar.gz", "payloadSize": int(size), "payloadSha256": sha, "notes": notes}
# ビルドしたソース(source: github / local、repo、branch、commit、subject、dirty)。車のアプリは知らないキーを読み飛ばす
if os.path.isfile(srcinfo):
    src = {}
    for line in open(srcinfo, encoding="utf-8"):
        k, _, v = line.rstrip("\n").partition("=")
        if k: src[k] = v
    m["source"] = src
json.dump(m, open(path, "w"), ensure_ascii=False, indent=2)
PY
file="opencruise-app-$build.ocapp"
tar -C "$tmp" -cf "$out/$file" manifest.json payload.tar.gz
echo "作りました: $out/$file(ビルド $build、$(du -h "$out/$file" | cut -f1))"
[ -n "$src_text" ] && echo "ソース: $src_text" || echo "ソース: 記録がありません(古いビルド)"
bash "$HERE/update-server.sh" --index-only "$out"
