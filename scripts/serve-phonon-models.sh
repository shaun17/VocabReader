#!/bin/sh
# 在本机 8765 端口提供 PhononModels/，供 Debug 包在模拟器里验证下载流程。
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/PhononModels/bundle.json" ] || "$ROOT/scripts/fetch-phonon-models.sh"
exec python3 -m http.server 8765 --bind 127.0.0.1 --directory "$ROOT/PhononModels"
