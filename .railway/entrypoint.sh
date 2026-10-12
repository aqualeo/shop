#!/bin/sh
set -eu

APP=/var/www/html
DATA="${PS_DATA_DIR:-/data}"
PERSISTED_DIRS="img upload download"

DB_SERVER="${DB_SERVER:-${MYSQLHOST:?DB_SERVER or MYSQLHOST is required}}"
DB_PORT="${DB_PORT:-${MYSQLPORT:-3306}}"
DB_USER="${DB_USER:-${MYSQLUSER:-root}}"
DB_PASSWD="${DB_PASSWD:-${MYSQLPASSWORD:-}}"
DB_NAME="${DB_NAME:-${MYSQLDATABASE:-railway}}"
DB_PREFIX="${DB_PREFIX:-ps_}"
# prestashop/base ships PS_DOMAIN="<to be defined>"; treat that placeholder as unset.
case "${PS_DOMAIN:-}" in
  ""|*"<"*) PS_DOMAIN="${RAILWAY_PUBLIC_DOMAIN:?Set PS_DOMAIN or generate a Railway domain}" ;;
esac
PS_DOMAIN=$(printf '%s' "$PS_DOMAIN" | tr -d '[:space:]' | sed -e 's#^[a-zA-Z]*://##' -e 's#/*$##')
echo "* Shop domain: [${PS_DOMAIN}]"
PS_LANGUAGE="${PS_LANGUAGE:-en}"
PS_COUNTRY="${PS_COUNTRY:-gb}"
ADMIN_MAIL="${ADMIN_MAIL:?ADMIN_MAIL is required for the first install}"
ADMIN_PASSWD="${ADMIN_PASSWD:?ADMIN_PASSWD is required for the first install}"

PORT="${PORT:-80}"
sed -i "s/Listen 80/Listen ${PORT}/" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

mkdir -p "$DATA"

echo "* Waiting for MySQL at ${DB_SERVER}:${DB_PORT} ..."
until mysql -h "$DB_SERVER" -P "$DB_PORT" -u "$DB_USER" ${DB_PASSWD:+-p"$DB_PASSWD"} -e "SELECT 1" >/dev/null 2>&1; do
  sleep 3
done

for dir in $PERSISTED_DIRS; do
  if [ ! -d "$DATA/$dir" ]; then
    cp -a "$APP/$dir" "$DATA/$dir"
  fi
  rm -rf "${APP:?}/$dir"
  ln -s "$DATA/$dir" "$APP/$dir"
done

if [ ! -f "$DATA/parameters.php" ]; then
  echo "* First start: installing PrestaShop ..."
  php "$APP/install-dev/index_cli.php" \
    --domain="$PS_DOMAIN" --db_server="$DB_SERVER:$DB_PORT" --db_name="$DB_NAME" --db_user="$DB_USER" \
    --db_password="$DB_PASSWD" --prefix="$DB_PREFIX" --db_create=0 \
    --firstname="${ADMIN_FIRSTNAME:-Admin}" --lastname="${ADMIN_LASTNAME:-Admin}" \
    --email="$ADMIN_MAIL" --password="$ADMIN_PASSWD" \
    --language="$PS_LANGUAGE" --country="$PS_COUNTRY" --timezone="${PS_TIMEZONE:-UTC}" \
    --all_languages=0 --newsletter=0 --send_email=0 --ssl=1 --fixtures="${PS_INSTALL_DEMO_PRODUCTS:-0}"
  mv "$APP/app/config/parameters.php" "$DATA/parameters.php"
fi

ln -sf "$DATA/parameters.php" "$APP/app/config/parameters.php"
rm -rf "$APP/install-dev"
chown -R www-data:www-data "$DATA" "$APP/var"

exec apache2-foreground
