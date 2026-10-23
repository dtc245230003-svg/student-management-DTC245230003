#!/usr/bin/env bash
# Sinh tệp cấu hình cho mysqld-exporter từ .env.
# Tệp sinh ra: monitoring/.my.cnf (đã gitignore, chmod 600, chỉ user của exporter đọc được).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
OUT_FILE="$ROOT_DIR/monitoring/.my.cnf"
EXPORTER_UID=65534   # user "nobody" mà image prom/mysqld-exporter chạy

if [ ! -f "$ENV_FILE" ]; then
  echo "LỖI: chưa có tệp .env. Hãy tạo từ .env.example trước." >&2
  exit 1
fi

# Đọc .env trong subshell, không in ra ngoài
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${EXPORTER_DB_USER:?Thiếu EXPORTER_DB_USER trong .env}"
: "${EXPORTER_DB_PASSWORD:?Thiếu EXPORTER_DB_PASSWORD trong .env}"
: "${DB_NAME:?Thiếu DB_NAME trong .env}"

umask 077
cat > "$OUT_FILE" <<EOF
[client]
user=${EXPORTER_DB_USER}
password=${EXPORTER_DB_PASSWORD}
host=db
port=3306
database=${DB_NAME}
EOF
chmod 600 "$OUT_FILE"

# Container exporter chạy bằng uid 65534 nên cần quyền đọc; "other" vẫn không có quyền
if command -v setfacl >/dev/null 2>&1; then
  setfacl -m "u:${EXPORTER_UID}:r" "$OUT_FILE"
else
  echo "CẢNH BÁO: không có setfacl, đặt tạm 644 cho $OUT_FILE" >&2
  chmod 644 "$OUT_FILE"
fi

echo "Đã tạo $OUT_FILE (không in nội dung)."
ls -l "$OUT_FILE"
command -v getfacl >/dev/null 2>&1 && getfacl -c "$OUT_FILE"
