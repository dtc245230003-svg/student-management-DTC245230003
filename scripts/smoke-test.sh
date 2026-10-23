#!/usr/bin/env bash
# Smoke test cho hệ thống quản lý sinh viên.
# - Không in mật khẩu: mọi truy vấn DB dùng biến môi trường trong container.
# - CRUD chỉ tạo bản ghi tạm SMK<timestamp>, luôn dọn dẹp bằng trap.
# - Không DROP / TRUNCATE / RESET, không sửa dữ liệu có sẵn.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

PASS=0
FAIL=0
SKIP=0
FAILED_CHECKS=()

pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_CHECKS+=("$1"); printf 'FAIL  %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP  %s\n' "$1"; }

# Lấy IP từ .env (chỉ đọc đúng biến SERVER_IP), fallback sang IP đầu tiên của máy.
SERVER_IP="${SERVER_IP:-}"
if [ -z "$SERVER_IP" ] && [ -f .env ]; then
  SERVER_IP="$(grep -E '^SERVER_IP=' .env | head -n1 | cut -d= -f2- | tr -d '[:space:]')"
fi
if [ -z "$SERVER_IP" ]; then
  SERVER_IP="$(hostname -I | awk '{print $1}')"
fi

BASE="https://${SERVER_IP}"
CURL=(curl -sk --connect-timeout 5 --max-time 15)

echo "=== SMOKE TEST: $BASE ==="
echo

db_query() {
  local sql="$1"
  docker compose exec -T -e SQL="$sql" db bash -c \
    'MYSQL_PWD="$APP_DB_PASSWORD" mysql -u"$APP_DB_USER" "$MYSQL_DATABASE" -N -B -e "$SQL"' 2>/dev/null
}

container_ip() {
  docker inspect -f '{{(index .NetworkSettings.Networks "student-management_monitoring").IPAddress}}' "$1" 2>/dev/null
}

http_code() {
  "${CURL[@]}" -o /dev/null -w '%{http_code}' "$1"
}

prom_value() {
  "${CURL[@]}" -G "$BASE/prometheus/api/v1/query" --data-urlencode "query=$1" 2>/dev/null |
    python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); r=d["data"]["result"]
    print(r[0]["value"][1] if r else "")
except Exception:
    print("")'
}

# ---------------- Trạng thái CRUD + cleanup ----------------
TS="$(date +%s)"
CLASS_CODE="SMK${TS}"
STUDENT_CODE="SMK${TS}"
STUDENT_EMAIL="smk${TS}@example.com"
CLASS_ID=""
STUDENT_ID=""
GRADE_ID=""
CLEANED=0

cleanup() {
  local rc=$?
  if [ "$CLEANED" -eq 1 ]; then
    return
  fi
  CLEANED=1

  # Chỉ xóa đúng bản ghi của lần chạy này (khớp cả id và mã SMK...).
  if [[ "${STUDENT_ID:-}" =~ ^[0-9]+$ ]]; then
    db_query "DELETE FROM students WHERE id=${STUDENT_ID} AND student_code='${STUDENT_CODE}'" >/dev/null
  elif [[ "${STUDENT_CODE:-}" =~ ^SMK[0-9]+$ ]]; then
    db_query "DELETE FROM students WHERE student_code='${STUDENT_CODE}'" >/dev/null
  fi
  if [[ "${CLASS_ID:-}" =~ ^[0-9]+$ ]]; then
    db_query "DELETE FROM classes WHERE id=${CLASS_ID} AND class_code='${CLASS_CODE}'" >/dev/null
  elif [[ "${CLASS_CODE:-}" =~ ^SMK[0-9]+$ ]]; then
    db_query "DELETE FROM classes WHERE class_code='${CLASS_CODE}'" >/dev/null
  fi

  local left
  left="$(db_query "SELECT (SELECT COUNT(*) FROM classes WHERE class_code='${CLASS_CODE}') + (SELECT COUNT(*) FROM students WHERE student_code='${STUDENT_CODE}')")"
  if [ "$left" != "0" ]; then
    printf 'CLEANUP FAILED: còn %s bản ghi (class_code=%s, student_code=%s)\n' \
      "${left:-?}" "$CLASS_CODE" "$STUDENT_CODE" >&2
    exit 1
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

# ---------------- 1. Compose và container ----------------
if docker compose config --quiet 2>/dev/null; then
  pass "Cấu hình Docker Compose hợp lệ"
else
  fail "Cấu hình Docker Compose không hợp lệ"
fi

EXPECTED_SERVICES="cadvisor db grafana loki mysqld-exporter nginx nginx-exporter phpmyadmin prometheus promtail web"
expected_sorted="$(printf '%s\n' $EXPECTED_SERVICES | sort | tr '\n' ' ' | sed 's/ $//')"
running_sorted="$(docker compose ps --services --filter status=running 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
if [ -n "$running_sorted" ] && [ "$running_sorted" = "$expected_sorted" ]; then
  pass "11 container đang chạy (đủ danh sách)"
else
  fail "Container đang chạy không khớp (nhận: ${running_sorted:-không đọc được})"
fi

# ---------------- 2. HTTP/HTTPS và header ----------------
read -r redir_code redir_url < <("${CURL[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "http://${SERVER_IP}/")
if [ "$redir_code" = "301" ] && [[ "$redir_url" == https://* ]]; then
  pass "HTTP chuyển hướng 301 sang HTTPS"
else
  fail "HTTP không chuyển hướng đúng (code=${redir_code:-?}, location=${redir_url:-?})"
fi

if [ "$(http_code "$BASE/")" = "200" ]; then
  pass "Trang chủ HTTPS trả 200"
else
  fail "Trang chủ HTTPS không trả 200"
fi

HEADERS="$("${CURL[@]}" -D - -o /dev/null "$BASE/")"
for h in strict-transport-security x-content-type-options x-frame-options referrer-policy permissions-policy content-security-policy; do
  if printf '%s' "$HEADERS" | grep -qi "^${h}:"; then
    pass "Security header: $h"
  else
    fail "Thiếu security header: $h"
  fi
done

for path in / /classes /students /grades /classes/new /students/new /grades/new /health /pma/ /grafana/login /prometheus/targets; do
  code="$(http_code "$BASE$path")"
  if [ "$code" = "200" ]; then
    pass "GET $path -> 200"
  else
    fail "GET $path -> ${code:-lỗi}"
  fi
done

GRAFANA_HEALTH="$("${CURL[@]}" "$BASE/grafana/api/health" 2>/dev/null)"
if printf '%s' "$GRAFANA_HEALTH" | grep -q '"database": *"ok"'; then
  pass "Grafana health: database ok"
else
  fail "Grafana health không báo database ok"
fi

# ---------------- 3. Cổng public ----------------
for p in 3000 8081; do
  if timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/${p}" 2>/dev/null; then
    fail "Cổng ${p} vẫn mở trên host"
  else
    pass "Cổng ${p} đã đóng trên host"
  fi
done

PUBLISHED_PORTS="$(docker compose ps --format '{{.Ports}}' 2>/dev/null)"
if printf '%s' "$PUBLISHED_PORTS" | grep -qE '0\.0\.0\.0:(3000|8081)->'; then
  fail "Có cổng 3000/8081 được publish trong compose"
else
  pass "Không publish cổng 3000/8081"
fi
if printf '%s' "$PUBLISHED_PORTS" | grep -q '0.0.0.0:80->' && printf '%s' "$PUBLISHED_PORTS" | grep -q '0.0.0.0:443->'; then
  pass "Chỉ Nginx publish 80 và 443"
else
  fail "Không thấy đủ cổng 80/443 của Nginx"
fi

# ---------------- 4. Prometheus / exporter ----------------
TARGETS_JSON="$("${CURL[@]}" "$BASE/prometheus/api/v1/targets?state=active" 2>/dev/null)"
TARGET_SUMMARY="$(printf '%s' "$TARGETS_JSON" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); ts=d["data"]["activeTargets"]
    jobs=sorted(t["labels"]["job"] for t in ts)
    up=sum(1 for t in ts if t["health"]=="up")
    joined=",".join(jobs)
    print(f"{up}/{len(ts)}:{joined}")
except Exception:
    print("")')"
if [ "$TARGET_SUMMARY" = "4/4:cadvisor,mysql,nginx,prometheus" ]; then
  pass "Prometheus: 4/4 target UP (cadvisor, mysql, nginx, prometheus)"
else
  fail "Prometheus target không đủ/không UP (${TARGET_SUMMARY:-không đọc được})"
fi

if [ "$(prom_value 'mysql_up')" = "1" ]; then
  pass "Metric mysql_up = 1"
else
  fail "Metric mysql_up khác 1 hoặc không có dữ liệu"
fi
if [ "$(prom_value 'nginx_up')" = "1" ]; then
  pass "Metric nginx_up = 1"
else
  fail "Metric nginx_up khác 1 hoặc không có dữ liệu"
fi
CONTAINER_SERIES="$(prom_value 'count(container_cpu_usage_seconds_total{name=~"sm-.+"})')"
if [[ "$CONTAINER_SERIES" =~ ^[0-9]+$ ]] && [ "$CONTAINER_SERIES" -ge 9 ]; then
  pass "cAdvisor có ${CONTAINER_SERIES} series container"
else
  fail "cAdvisor không đủ series container (${CONTAINER_SERIES:-không đọc được})"
fi

declare -A EXPORTERS=(
  [sm-cadvisor]="8080/metrics"
  [sm-nginx-exporter]="9113/metrics"
  [sm-mysqld-exporter]="9104/metrics"
  [sm-prometheus]="9090/prometheus/metrics"
  [sm-promtail]="9080/metrics"
)
for name in "${!EXPORTERS[@]}"; do
  ip="$(container_ip "$name")"
  path="${EXPORTERS[$name]}"
  if [ -z "$ip" ]; then
    skip "$name: không lấy được IP container"
    continue
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 10 "http://${ip}:${path}")"
  if [ "$code" = "200" ]; then
    pass "$name :${path} -> 200"
  else
    fail "$name :${path} -> ${code:-lỗi}"
  fi
done

# ---------------- 5. Loki ----------------
LOKI_IP="$(container_ip sm-loki)"
if [ -z "$LOKI_IP" ]; then
  skip "Loki: không lấy được IP container"
else
  READY_BODY=""
  for _ in 1 2 3 4 5; do
    READY_BODY="$(curl -s --connect-timeout 3 --max-time 10 "http://${LOKI_IP}:3100/ready")"
    [ "$READY_BODY" = "ready" ] && break
    sleep 2
  done
  if [ "$READY_BODY" = "ready" ]; then
    pass "Loki /ready = ready"
  else
    fail "Loki chưa ready (${READY_BODY:-không phản hồi})"
  fi
  LABELS="$(curl -s --connect-timeout 3 --max-time 10 "http://${LOKI_IP}:3100/loki/api/v1/label/service/values")"
  if printf '%s' "$LABELS" | grep -q '"web"' && printf '%s' "$LABELS" | grep -q '"nginx"'; then
    pass "Loki có nhãn service web và nginx"
  else
    fail "Loki thiếu nhãn service web/nginx"
  fi
  START_NS="$(( $(date +%s) - 900 ))000000000"
  END_NS="$(date +%s)000000000"
  LOKI_Q="$(curl -sG --connect-timeout 3 --max-time 10 "http://${LOKI_IP}:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={project="student-management"}' \
    --data-urlencode 'limit=1' \
    --data-urlencode "start=${START_NS}" \
    --data-urlencode "end=${END_NS}")"
  LOG_STREAMS="$(printf '%s' "$LOKI_Q" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(len(d["data"]["result"]))
except Exception:
    print("")')"
  if [[ "$LOG_STREAMS" =~ ^[0-9]+$ ]] && [ "$LOG_STREAMS" -gt 0 ]; then
    pass "Loki truy vấn LogQL có dữ liệu (${LOG_STREAMS} stream)"
  else
    fail "Loki không trả log trong 15 phút gần nhất"
  fi
fi

# ---------------- 6. Database trước CRUD ----------------
TABLES="$(db_query 'SHOW TABLES' | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$TABLES" = "classes grades students" ]; then
  pass "Database có đủ bảng classes, grades, students"
else
  fail "Database thiếu bảng (nhận: ${TABLES:-không đọc được})"
fi

INITIAL_COUNTS="$(db_query 'SELECT (SELECT COUNT(*) FROM classes), (SELECT COUNT(*) FROM students), (SELECT COUNT(*) FROM grades)')"
if [ "$INITIAL_COUNTS" = $'3\t8\t10' ]; then
  pass "Số dòng ban đầu đúng 3 lớp / 8 sinh viên / 10 điểm"
else
  fail "Số dòng ban đầu KHÁC 3/8/10 (nhận: ${INITIAL_COUNTS:-không đọc được}) — dừng CRUD"
  echo
  printf 'Tổng kết: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
  exit 1
fi

# ---------------- 7. CRUD tạm ----------------
echo
echo "--- CRUD tạm: class=${CLASS_CODE}, student=${STUDENT_CODE} ---"

post_form() {
  local url="$1"; shift
  "${CURL[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' -X POST "$url" "$@"
}

post_body_code() {
  local url="$1"; shift
  "${CURL[@]}" -X POST "$url" -w $'\n%{http_code}' "$@"
}

# Tạo lớp
read -r code redirect < <(post_form "$BASE/classes" \
  --data-urlencode "class_code=${CLASS_CODE}" \
  --data-urlencode "class_name=Smoke Test ${TS}")
if [ "$code" = "302" ] && [[ "$redirect" == *"/classes?msg="* ]]; then
  pass "Tạo lớp tạm"
else
  fail "Tạo lớp tạm thất bại (code=${code:-?}, redirect=${redirect:-?})"
  exit 1
fi
CLASS_ID="$(db_query "SELECT id FROM classes WHERE class_code='${CLASS_CODE}' LIMIT 1")"
if [[ "$CLASS_ID" =~ ^[0-9]+$ ]]; then
  pass "Lấy được ID lớp tạm (${CLASS_ID})"
else
  fail "Không lấy được ID lớp tạm — dừng để tránh dữ liệu sót"
  exit 1
fi

# Tạo sinh viên
read -r code redirect < <(post_form "$BASE/students" \
  --data-urlencode "student_code=${STUDENT_CODE}" \
  --data-urlencode "full_name=Smoke Test" \
  --data-urlencode "email=${STUDENT_EMAIL}" \
  --data-urlencode "class_id=${CLASS_ID}")
if [ "$code" = "302" ] && [[ "$redirect" == *"/students?msg="* ]]; then
  pass "Tạo sinh viên tạm"
else
  fail "Tạo sinh viên tạm thất bại (code=${code:-?}, redirect=${redirect:-?})"
  exit 1
fi
STUDENT_ID="$(db_query "SELECT id FROM students WHERE student_code='${STUDENT_CODE}' LIMIT 1")"
if [[ "$STUDENT_ID" =~ ^[0-9]+$ ]]; then
  pass "Lấy được ID sinh viên tạm (${STUDENT_ID})"
else
  fail "Không lấy được ID sinh viên tạm — dừng để tránh dữ liệu sót"
  exit 1
fi

# Tạo điểm
SUBJECT="Smoke Subject ${TS}"
read -r code redirect < <(post_form "$BASE/grades" \
  --data-urlencode "student_id=${STUDENT_ID}" \
  --data-urlencode "subject=${SUBJECT}" \
  --data-urlencode "score=7.5")
if [ "$code" = "302" ] && [[ "$redirect" == *"/grades?msg="* ]]; then
  pass "Tạo điểm tạm (7.5)"
else
  fail "Tạo điểm tạm thất bại (code=${code:-?}, redirect=${redirect:-?})"
  exit 1
fi
GRADE_ID="$(db_query "SELECT id FROM grades WHERE student_id=${STUDENT_ID} AND subject='${SUBJECT}' LIMIT 1")"
if [[ "$GRADE_ID" =~ ^[0-9]+$ ]]; then
  pass "Lấy được ID điểm tạm (${GRADE_ID})"
else
  fail "Không lấy được ID điểm tạm — dừng để tránh dữ liệu sót"
  exit 1
fi

# Cập nhật điểm
read -r code redirect < <(post_form "$BASE/grades/${GRADE_ID}/update" \
  --data-urlencode "student_id=${STUDENT_ID}" \
  --data-urlencode "subject=${SUBJECT}" \
  --data-urlencode "score=8.5")
if [ "$code" = "302" ] && [[ "$redirect" == *"/grades?msg="* ]]; then
  pass "Cập nhật điểm tạm"
else
  fail "Cập nhật điểm tạm thất bại (code=${code:-?}, redirect=${redirect:-?})"
fi
SCORE_NOW="$(db_query "SELECT score FROM grades WHERE id=${GRADE_ID}")"
if [ "$SCORE_NOW" = "8.50" ]; then
  pass "Điểm trong DB đã cập nhật thành 8.50"
else
  fail "Điểm trong DB không đúng (${SCORE_NOW:-không đọc được})"
fi

# Kiểm tra validate phía server (không tạo bản ghi)
RESP="$(post_body_code "$BASE/students" \
  --data-urlencode "student_code=SMKV${TS}" \
  --data-urlencode "full_name=Smoke Invalid" \
  --data-urlencode "email=abc" \
  --data-urlencode "class_id=${CLASS_ID}")"
code="${RESP##*$'\n'}"
body="${RESP%$'\n'*}"
if [ "$code" = "400" ] && printf '%s' "$body" | grep -q 'Email không hợp lệ'; then
  pass "Chặn email sai định dạng (400)"
else
  fail "Không chặn email sai (code=${code:-?})"
fi

RESP="$(post_body_code "$BASE/grades" \
  --data-urlencode "student_id=${STUDENT_ID}" \
  --data-urlencode "subject=Smoke Invalid" \
  --data-urlencode "score=11")"
code="${RESP##*$'\n'}"
body="${RESP%$'\n'*}"
if [ "$code" = "400" ] && printf '%s' "$body" | grep -q 'Điểm phải là số từ 0 đến 10'; then
  pass "Chặn điểm ngoài 0–10 (400)"
else
  fail "Không chặn điểm 11 (code=${code:-?})"
fi

# Xóa lớp khi còn sinh viên -> bị chặn
read -r code redirect < <(post_form "$BASE/classes/${CLASS_ID}/delete")
if [ "$code" = "302" ] && [[ "$redirect" == *"err="* ]]; then
  pass "Chặn xóa lớp còn sinh viên (ON DELETE RESTRICT)"
else
  fail "Không chặn xóa lớp còn sinh viên (code=${code:-?}, redirect=${redirect:-?})"
fi
STILL_CLASS="$(db_query "SELECT COUNT(*) FROM classes WHERE id=${CLASS_ID}")"
if [ "$STILL_CLASS" = "1" ]; then
  pass "Lớp vẫn tồn tại sau khi bị chặn xóa"
else
  fail "Lớp đã biến mất dù phải bị chặn (count=${STILL_CLASS:-?})"
fi

# Xóa sinh viên -> điểm cascade
read -r code redirect < <(post_form "$BASE/students/${STUDENT_ID}/delete")
if [ "$code" = "302" ] && [[ "$redirect" == *"/students?msg="* ]]; then
  pass "Xóa sinh viên tạm"
else
  fail "Xóa sinh viên tạm thất bại (code=${code:-?}, redirect=${redirect:-?})"
fi
STUDENT_LEFT="$(db_query "SELECT COUNT(*) FROM students WHERE id=${STUDENT_ID}")"
GRADE_LEFT="$(db_query "SELECT COUNT(*) FROM grades WHERE student_id=${STUDENT_ID}")"
if [ "$STUDENT_LEFT" = "0" ] && [ "$GRADE_LEFT" = "0" ]; then
  pass "Điểm của sinh viên bị xóa theo (ON DELETE CASCADE)"
else
  fail "Cascade chưa đúng (student=${STUDENT_LEFT:-?}, grade=${GRADE_LEFT:-?})"
fi

# Xóa lớp
read -r code redirect < <(post_form "$BASE/classes/${CLASS_ID}/delete")
if [ "$code" = "302" ] && [[ "$redirect" == *"/classes?msg="* ]]; then
  pass "Xóa lớp tạm"
else
  fail "Xóa lớp tạm thất bại (code=${code:-?}, redirect=${redirect:-?})"
fi
CLASS_LEFT="$(db_query "SELECT COUNT(*) FROM classes WHERE id=${CLASS_ID}")"
if [ "$CLASS_LEFT" = "0" ]; then
  pass "Lớp tạm đã được xóa khỏi DB"
else
  fail "Lớp tạm còn trong DB (count=${CLASS_LEFT:-?})"
fi

# ---------------- 8. Đối chiếu dữ liệu sau ----------------
FINAL_COUNTS="$(db_query 'SELECT (SELECT COUNT(*) FROM classes), (SELECT COUNT(*) FROM students), (SELECT COUNT(*) FROM grades)')"
if [ "$FINAL_COUNTS" = "$INITIAL_COUNTS" ]; then
  pass "Số dòng sau test khớp ban đầu (${INITIAL_COUNTS//$'\t'//})"
else
  fail "Số dòng sau test KHÁC ban đầu (trước=${INITIAL_COUNTS:-?}, sau=${FINAL_COUNTS:-?})"
fi
SMK_LEFT="$(db_query "SELECT (SELECT COUNT(*) FROM classes WHERE class_code='${CLASS_CODE}') + (SELECT COUNT(*) FROM students WHERE student_code='${STUDENT_CODE}')")"
if [ "$SMK_LEFT" = "0" ]; then
  pass "Không còn bản ghi SMK của lần chạy này"
else
  fail "Còn ${SMK_LEFT:-?} bản ghi SMK sót lại"
fi
ORPHANS="$(db_query 'SELECT COUNT(*) FROM grades g LEFT JOIN students s ON s.id = g.student_id WHERE s.id IS NULL')"
if [ "$ORPHANS" = "0" ]; then
  pass "Không có điểm mồ côi"
else
  fail "Có ${ORPHANS:-?} điểm mồ côi"
fi

# ---------------- Tổng kết ----------------
echo
printf 'Tổng kết: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  printf 'Kiểm tra thất bại:\n'
  for c in "${FAILED_CHECKS[@]}"; do printf ' - %s\n' "$c"; done
  exit 1
fi
exit 0
