#!/bin/sh
# 下载 Phonon 31m 的 Core ML 模型包到 PhononModels/，供 Debug 内置或本机下载服务使用。
set -eu

VERSION="v0.4.0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/PhononModels"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fL --progress-bar -o "$TMP/models.zip" \
  "https://github.com/gradium-ai/xn-ptts/releases/download/$VERSION/phonon-31m-en-coreml.zip"
unzip -q "$TMP/models.zip" -d "$TMP/unzipped"
rm -rf "$DEST"
mv "$TMP/unzipped/phonon-31m-en-coreml" "$DEST"
echo "Installed Phonon models to $DEST ($(du -sh "$DEST" | cut -f1))"
