#!/bin/bash
# Создаёт пользователя только для чтения, под которым Grafana ходит в БД.
# Выполняется один раз при первой инициализации тома PostgreSQL.
set -e

: "${GRAFANA_DB_PASSWORD:?Переменная GRAFANA_DB_PASSWORD не задана}"

psql -v ON_ERROR_STOP=1 \
     -v ro_pass="$GRAFANA_DB_PASSWORD" \
     -v dbname="$POSTGRES_DB" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
CREATE ROLE grafana_ro LOGIN PASSWORD :'ro_pass';
GRANT CONNECT ON DATABASE :"dbname" TO grafana_ro;
GRANT USAGE ON SCHEMA public TO grafana_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_ro;
-- Хеши паролей и токенов Grafana читать не нужно
REVOKE ALL ON APP_USER, API_TOKEN, MONITORING_SOURCE FROM grafana_ro;
EOSQL
