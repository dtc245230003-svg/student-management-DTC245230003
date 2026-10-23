#!/usr/bin/env bash
# Sinh chứng chỉ TLS tự ký cho Nginx.
#
# Cách dùng:
#   ./scripts/gen-cert.sh                 # tự lấy IP đầu tiên của máy, tên ảo student.local
#   ./scripts/gen-cert.sh 192.168.44.131 student.local
#   FORCE_REGEN=1 ./scripts/gen-cert.sh   # tạo lại dù đã có chứng chỉ
#
# Khóa riêng nằm trong nginx/certs/ và đã được .gitignore chặn commit.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$ROOT_DIR/nginx/certs"
CERT_FILE="$CERT_DIR/server.crt"
KEY_FILE="$CERT_DIR/server.key"
DAYS=825

IP="${1:-${CERT_IP:-$(hostname -I | awk '{print $1}')}}"
DNS_NAME="${2:-${CERT_DNS:-student.local}}"

if [ -z "$IP" ]; then
  echo "LỖI: không xác định được IP. Hãy truyền tham số, ví dụ: $0 192.168.44.131 student.local" >&2
  exit 1
fi

mkdir -p "$CERT_DIR"

if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && [ "${FORCE_REGEN:-0}" != "1" ]; then
  echo "Đã có chứng chỉ tại $CERT_DIR (dùng FORCE_REGEN=1 để tạo lại)."
  openssl x509 -in "$CERT_FILE" -noout -subject -dates -ext subjectAltName
  exit 0
fi

SAN="DNS:${DNS_NAME},DNS:localhost,IP:${IP},IP:127.0.0.1"

openssl req -x509 -newkey rsa:2048 -sha256 -days "$DAYS" -nodes \
  -keyout "$KEY_FILE" -out "$CERT_FILE" \
  -subj "/C=VN/ST=Thai Nguyen/L=Thai Nguyen/O=ICTU/OU=Khoa CNTT/CN=${DNS_NAME}" \
  -addext "subjectAltName=${SAN}" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1

chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

# Nginx chạy bằng user 101 (image nginx-unprivileged) nên cần quyền đọc khóa.
# Dùng ACL để chỉ uid 101 đọc được, "other" vẫn không có quyền gì.
if command -v setfacl >/dev/null 2>&1; then
  setfacl -m u:101:r "$KEY_FILE"
else
  echo "CẢNH BÁO: không có setfacl. Đặt tạm quyền 644 cho khóa để container đọc được." >&2
  chmod 644 "$KEY_FILE"
fi

echo "Đã tạo chứng chỉ tự ký:"
echo "  Tệp:     nginx/certs/server.crt, nginx/certs/server.key (khóa chỉ chủ sở hữu đọc được)"
echo "  Hạn:     $DAYS ngày"
echo "  SAN:     $SAN"
openssl x509 -in "$CERT_FILE" -noout -subject -dates -ext subjectAltName
