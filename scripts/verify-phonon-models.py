#!/usr/bin/env python3
"""确认 R2 上的 Phonon 模型与本地 PhononModels/ 一致。

只发 HEAD 请求：R2 单次上传对象的 ETag 就是内容 MD5，与本地文件比对即可，
不必下载 163 MB，也不受本机网络断流影响。
"""
import hashlib
import json
import pathlib
import sys
import urllib.parse
import urllib.request

base = (sys.argv[1] if len(sys.argv) > 1 else "https://assets.wenmsg.fun/phonon/31m-en/v0.4.0").rstrip("/")
root = pathlib.Path(__file__).resolve().parent.parent / "PhononModels"

paths = [f["path"] for f in json.loads((root / "bundle.json").read_text())["files"]] + ["bundle.json"]
failures = 0
for path in paths:
    # Cloudflare 会拦截 Python 默认 User-Agent，iOS 的 CFNetwork 不受影响。
    request = urllib.request.Request(
        f"{base}/{urllib.parse.quote(path)}",
        method="HEAD",
        headers={"User-Agent": "VocabReader-verify/1.0"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        etag = response.headers["ETag"].strip('"')
        length = int(response.headers["Content-Length"])

    local = (root / path).read_bytes()
    if etag != hashlib.md5(local).hexdigest() or length != len(local):
        failures += 1
        print(f"MISMATCH {path}: remote {length} bytes etag {etag}, local {len(local)} bytes")

print(f"{len(paths) - failures}/{len(paths)} objects match {base}")
sys.exit(1 if failures else 0)
