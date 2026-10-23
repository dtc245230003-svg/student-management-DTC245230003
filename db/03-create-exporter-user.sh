#!/bin/bash
# Chạy tự động một lần khi khởi tạo DB lần đầu.
# Tạo tài khoản riêng cho mysqld-exporter với QUYỀN TỐI THIỂU:
#   - PROCESS, REPLICATION CLIENT: đọc trạng thái server (mysql_up, threads, queries)
#   - SELECT trên đúng database ứng dụng
# Giới hạn MAX_USER_CONNECTIONS nhỏ để tránh exporter chiếm hết kết nối.
set -e
mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<EOSQL
CREATE USER IF NOT EXISTS '${EXPORTER_DB_USER}'@'%' IDENTIFIED BY '${EXPORTER_DB_PASSWORD}'
  WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT ON *.* TO '${EXPORTER_DB_USER}'@'%';
GRANT SELECT ON \`${MYSQL_DATABASE}\`.* TO '${EXPORTER_DB_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL
