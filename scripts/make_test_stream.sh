#!/usr/bin/env bash
# 開発用: Android Auto の映像データの代わりに使うテスト H.264 を生成する。
# 使い方: scripts/make_test_stream.sh [出力ファイル]   (ffmpeg + libx264 が必要)
# 800x480 / 30fps / baseline、各アクセスユニット先頭に AUD を入れる(TestVideoFeeder が AUD で分割するため)。
set -euo pipefail
out="${1:-test_800x480.h264}"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=800x480:rate=30" -t 6 \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -x264-params "aud=1:keyint=30:repeat-headers=1" \
  -f h264 "$out"
echo "生成しました: $out"
