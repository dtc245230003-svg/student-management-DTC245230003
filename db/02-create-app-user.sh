#!/bin/bash
# Chạy tự động một lần khi khởi tạo DB lần đầu.
# Tạo tài khoản ứng dụng với QUYỀN TỐI THIỂU: chỉ SELECT/INSERT/UPDATE/DELETE
# trên đúng một database; không có DROP, ALTER, CREATE, GRANT.
set -e
mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<EOSQL
CREATE USER '${APP_DB_USER}'@'%' IDENTIFIED BY '${APP_DB_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`${MYSQL_DATABASE}\`.* TO '${APP_DB_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL
