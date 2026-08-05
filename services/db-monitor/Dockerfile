ARG M2D_ENABLE_DB_REPLICATION='no'

# Only useful once replication exists — gated on the same flag, same busybox-placeholder
# pattern already used by every other M2D_ENABLE_* toggle in this repo.
FROM busybox:1.36 AS m2d_db_monitor_no
CMD ["tail", "-f", "/dev/null"]

FROM alpine:3.19 AS m2d_db_monitor_yes

RUN apk add --no-cache mysql-client bash python3

COPY services/db-monitor/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY services/db-monitor/monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/monitor.sh

EXPOSE 8080

CMD ["/usr/local/bin/entrypoint.sh"]

FROM m2d_db_monitor_${M2D_ENABLE_DB_REPLICATION} AS m2d_db_monitor
