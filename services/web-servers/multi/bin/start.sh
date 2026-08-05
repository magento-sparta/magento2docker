#!/bin/bash
set -e

source /usr/local/bin/m2d-lib.sh

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

# Start a PHP-FPM pool for the default version, plus whatever versions the projects
# already installed in this container actually use — not every version unconditionally.
# Warming a pool nothing has installed just burns RAM/CPU for the life of the container;
# a version a NEW install picks that isn't started yet is handled separately by
# m2install.sh's own ensure_fpm_pool call right after a successful install.
mkdir -p /run/php
ensure_fpm_pool "$DEFAULT_PHP"
for conf in "$APACHE_ROOT"/*/.m2install.conf; do
    [[ -f "$conf" ]] || continue
    ver=$(grep -m1 '^M2D_PHP_VERSION=' "$conf" | cut -d= -f2-)
    [[ -n "$ver" ]] && ensure_fpm_pool "$ver"
done

service ssh start
service cron start

# Re-start any PWA dev servers that were running before container restart.
# Must run after PHP-FPM is up so pwa-start can reach the Magento backend.
for pidfile in /var/run/pwa/*.pid; do
    [ -f "$pidfile" ] || continue
    project=$(basename "$pidfile" .pid)
    pwa-start "$project" 2>/dev/null || true
done

echo "[start.sh] default PHP: ${DEFAULT_PHP}"
exec apache2ctl -D FOREGROUND
