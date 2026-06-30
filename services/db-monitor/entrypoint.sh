#!/bin/bash
mkdir -p /var/www
python3 -m http.server 8080 --directory /var/www &
exec /usr/local/bin/monitor.sh
