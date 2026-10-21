#!/bin/sh
# 把 PhononModels/ 按原目录结构上传到 Cloudflare R2，App 通过 PhononModels.download(from:) 逐个文件下载。
# 需要 wrangler 已登录或设置 CLOUDFLARE_API_TOKEN；账号级 token 不能查询 memberships，所以显式指定账号。
# 路径带模型版本，更新模型时换新前缀，不覆盖旧版本 App 正在用的文件。
set -eu

BUCKET="${BUCKET:-vocabreader-assets}"
PREFIX="${PREFIX:-phonon/31m-en/v0.4.0}"
WRANGLER="npx --yes wrangler@4.85.0"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-14bc5b693b33c32721b04310dc7c72a7}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT/PhononModels"
[ -f bundle.json ] || { echo "PhononModels/bundle.json 不存在，先运行 scripts/fetch-phonon-models.sh" >&2; exit 1; }

# 先传 bundle.json 列出的文件，最后传 bundle.json，保证客户端拿到清单时文件已全部就位。
python3 -I -c 'import json; [print(f["path"]) for f in json.load(open("bundle.json"))["files"]]' |
while IFS= read -r file; do
  echo "→ $file"
  $WRANGLER r2 object put "$BUCKET/$PREFIX/$file" --file "$file" --remote \
    --cache-control "public, max-age=31536000, immutable" </dev/null
done

$WRANGLER r2 object put "$BUCKET/$PREFIX/bundle.json" --file bundle.json --remote \
  --content-type application/json --cache-control "public, max-age=300"

echo "Uploaded to r2://$BUCKET/$PREFIX"
