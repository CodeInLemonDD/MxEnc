import base64
import json
import time
import hmac
import hashlib
from pathlib import Path


def make_license(secret: str, device_id: str, ttl_days: int = 365) -> str:
    exp = int(time.time()) + ttl_days * 24 * 3600
    message = f"{device_id}|{exp}".encode('utf-8')
    sig = hmac.new(secret.encode('utf-8'), message, hashlib.sha256).digest()
    lic = {
        'deviceId': device_id,
        'exp': exp,
        'sig': base64.b64encode(sig).decode('ascii'),
    }
    return base64.urlsafe_b64encode(json.dumps(lic, ensure_ascii=False).encode('utf-8')).decode('ascii')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--secret', default='maoxiaoencoder', help='共享密钥')
    parser.add_argument('--device', required=True, help='设备ID')
    parser.add_argument('--days', type=int, default=365, help='有效期天数')
    args = parser.parse_args()

    lic = make_license(args.secret, args.device, args.days)
    print('卡密:')
    print(lic)
