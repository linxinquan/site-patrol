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

# COS 凭证（cos_config.py 被 gitignore 排除，缺失时用环境变量+默认值兜底）
try:
    import cos_config as C
except ImportError:
    class C:
        COS_BUCKET = os.environ.get("COS_BUCKET", "")
        COS_REGION = os.environ.get("COS_REGION", "ap-guangzhou")
        COS_SECRET_ID = os.environ.get("COS_SECRET_ID", "")
        COS_SECRET_KEY = os.environ.get("COS_SECRET_KEY", "")
        COS_HOST = f"{COS_BUCKET}.cos.{COS_REGION}.myqcloud.com"

if not (C.COS_SECRET_ID and C.COS_SECRET_KEY):
    raise ImportError(
        "未配置腾讯云 COS 凭证（COS_SECRET_ID/COS_SECRET_KEY）。\n"
        "请复制 server/.env.example 为 server/cos_config.py 并填入真实凭证，"
        "或设置同名环境变量。"
    )

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
