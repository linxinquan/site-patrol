# -*- coding: utf-8 -*-
"""
腾讯云 COS 上传工具（基于官方 cos-python-sdk-v5）。
用于把 DWG 上传到 COS 生成公网 URL，供浩辰 dwgToOcf fileUrl 方式下载。

用法：
  from cos_upload import upload_file
  url = upload_file(local_path, cos_key)   # 返回公网 URL
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cos_config as C

try:
    from qcloud_cos import CosConfig, CosS3Client
except ImportError as e:
    raise ImportError("请先安装腾讯云 COS SDK: pip install cos-python-sdk-v5") from e

_config = CosConfig(
    Region=C.COS_REGION,
    SecretId=C.COS_SECRET_ID,
    SecretKey=C.COS_SECRET_KEY,
)
_client = CosS3Client(_config)


def upload_file(local_path, cos_key, content_type="application/octet-stream"):
    """上传文件到 COS，返回公网 URL。"""
    if not os.path.exists(local_path):
        raise FileNotFoundError(local_path)
    cos_key = cos_key.lstrip("/")
    with open(local_path, "rb") as f:
        resp = _client.put_object(
            Bucket=C.COS_BUCKET,
            Body=f,
            Key=cos_key,
            ContentType=content_type,
        )
    etag = resp.get("ETag", "")
    return f"https://{C.COS_HOST}/{cos_key}"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python cos_upload.py <本地文件> [cos_key]")
        sys.exit(1)
    src = sys.argv[1]
    key = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(src)
    url = upload_file(src, key)
    print("上传成功:", url)
