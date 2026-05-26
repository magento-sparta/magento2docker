#!/bin/bash
set -e

DEFAULT_PHP="${M2D_WEB_SERVER_PHP_VERSION:-8.3}"

# Expose variables to Apache vhost config
APACHE_ROOT="${M2D_APACHE_ROOT_DIRECTORY:-/var/www/html}"
mkdir -p /etc/apache2/conf-enabled
cat > /etc/apache2/conf-enabled/m2d.conf <<EOF
Define M2D_DEFAULT_PHP_VERSION ${DEFAULT_PHP}
Define M2D_APACHE_ROOT_DIRECTORY ${APACHE_ROOT}
EOF

# Ensure PWA port map exists (RewriteMap txt: requires file present at startup)
mkdir -p /usr/local/etc /var/log/pwa /var/run/pwa
touch /usr/local/etc/pwa-ports.map
chown magento:magento /usr/local/etc/pwa-ports.map /var/log/pwa /var/run/pwa 2>/dev/null || true
chmod 664 /usr/local/etc/pwa-ports.map 2>/dev/null || true

# Re-start any PWA dev servers that were running before container restart
for pidfile in /var/run/pwa/*.pid; do
    [ -f "$pidfile" ] || continue
    project=$(basename "$pidfile" .pid)
    pwa-start "$project" 2>/dev/null || true
done

# Start a PHP-FPM pool for every installed version
mkdir -p /run/php
for ver in 8.1 8.2 8.3 8.4 8.5; do
    bin="php-fpm${ver}"
    if command -v "$bin" &>/dev/null; then
        "$bin" --daemonize --fpm-config "/etc/php/${ver}/fpm/php-fpm.conf"
        echo "[start.sh] php-fpm${ver} started"
    else
        echo "[start.sh] php-fpm${ver} not found, skipping"
    fi
done

service ssh start
service cron start

echo "[start.sh] default PHP: ${DEFAULT_PHP}"
exec apache2ctl -D FOREGROUND
