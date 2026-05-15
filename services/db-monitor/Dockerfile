FROM alpine:3.19

RUN apk add --no-cache mysql-client bash python3

COPY services/db-monitor/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY services/db-monitor/monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/monitor.sh

EXPOSE 8080

CMD ["/usr/local/bin/entrypoint.sh"]
