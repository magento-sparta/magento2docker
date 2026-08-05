#!/bin/bash

INTERVAL=${M2D_DB_MONITOR_INTERVAL:-30}
MASTER_HOST="db"
SLAVE_HOST="db_slave"
# Array (not a string) so it expands to discrete args without relying on
# unquoted word-splitting, which zsh does not do by default.
MYSQL_OPTS=(-u root --password= --connect-timeout=5 -N -s)
HTML_FILE="/var/www/index.html"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# html_escape TEXT — MySQL error text (Last_IO_Error/Last_SQL_Error) can echo back
# data influenced by replicated statements, and this dashboard is served with no
# auth — escape before it ever reaches write_html's here-doc.
html_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

write_html() {
    local master_level="$1" master_line_raw="$2"
    local slave_level="$3"  slave_line_raw="$4"
    local master_line slave_line
    master_line=$(html_escape "$master_line_raw")
    slave_line=$(html_escape "$slave_line_raw")

    color() {
        case "$1" in
            OK)    echo "#2ecc71" ;;
            WARN)  echo "#f39c12" ;;
            ERROR) echo "#e74c3c" ;;
            *)     echo "#95a5a6" ;;
        esac
    }

    cat > "$HTML_FILE" <<HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="5">
  <title>DB Monitor</title>
  <style>
    body { font-family: monospace; background: #1a1a2e; color: #eee; padding: 2rem; }
    h1   { color: #a29bfe; margin-bottom: 0.25rem; }
    .ts  { color: #636e72; font-size: 0.85rem; margin-bottom: 2rem; }
    .card {
      background: #16213e; border-radius: 8px; padding: 1.25rem 1.5rem;
      margin-bottom: 1rem; border-left: 5px solid $(color "$master_level");
    }
    .card.slave { border-left-color: $(color "$slave_level"); }
    .label { font-size: 0.75rem; text-transform: uppercase; color: #a29bfe; margin-bottom: 0.4rem; }
    .status { font-size: 1rem; word-break: break-all; }
    .badge {
      display: inline-block; padding: 2px 10px; border-radius: 4px;
      font-size: 0.75rem; font-weight: bold; margin-right: 0.5rem;
      background: $(color "$master_level"); color: #fff;
    }
    .badge.slave { background: $(color "$slave_level"); }
    .term { color: #a29bfe; padding: 0.3rem 0.5rem 0.3rem 0; vertical-align: top; white-space: nowrap; }
    td   { padding: 0.3rem 0.5rem; vertical-align: top; border-bottom: 1px solid #2d2d4e; }
  </style>
</head>
<body>
  <h1>DB Monitor</h1>
  <div class="ts">Last check: $(date '+%Y-%m-%d %H:%M:%S') &nbsp;·&nbsp; refresh every ${INTERVAL}s</div>

  <div class="card">
    <div class="label">Master &mdash; ${MASTER_HOST}</div>
    <div class="status"><span class="badge">${master_level}</span>${master_line}</div>
  </div>

  <div class="card slave">
    <div class="label">Slave &mdash; ${SLAVE_HOST}</div>
    <div class="status"><span class="badge slave">${slave_level}</span>${slave_line}</div>
  </div>

  <details id="glossary" style="margin-top:2rem;">
    <summary style="cursor:pointer; color:#a29bfe; font-size:0.85rem; user-select:none;">Glossary</summary>
    <table style="margin-top:1rem; border-collapse:collapse; width:100%; font-size:0.85rem;">
      <colgroup><col style="width:14rem"><col></colgroup>
      <tbody>
        <tr><td class="term">server_id</td><td>Unique numeric ID for this server instance. Master and slave must differ; used to prevent replication loops.</td></tr>
        <tr><td class="term">log_bin</td><td>Whether binary logging is enabled on the master. Required for replication — the slave reads these logs to replay changes.</td></tr>
        <tr><td class="term">binlog_format</td><td>How changes are written to the binary log. ROW records the actual row data changed; STATEMENT records the SQL; MIXED uses both.</td></tr>
        <tr><td class="term">file</td><td>Current binary log file on the master (e.g. mysql-bin.000003). The slave reads from this file to stay in sync.</td></tr>
        <tr><td class="term">pos</td><td>Byte offset within the current binary log file. Together with file, this marks the master's exact replication position.</td></tr>
        <tr><td class="term">io</td><td>Slave I/O thread status. Reads binary log events from the master and writes them to the relay log. Must be Yes for replication to work.</td></tr>
        <tr><td class="term">sql</td><td>Slave SQL thread status. Replays events from the relay log against the slave database. Must be Yes for replication to work.</td></tr>
        <tr><td class="term">lag</td><td>Seconds the slave is behind the master. 0 means fully caught up. High values indicate the slave is struggling to keep up with write load.</td></tr>
        <tr><td class="term">io_err</td><td>Last error reported by the I/O thread (e.g. auth failure, network issue). Empty when healthy.</td></tr>
        <tr><td class="term">sql_err</td><td>Last error reported by the SQL thread (e.g. duplicate key, missing row). Empty when healthy.</td></tr>
      </tbody>
    </table>
  </details>
  <script>
    var g = document.getElementById('glossary');
    if (localStorage.getItem('glossary') === 'open') g.open = true;
    g.addEventListener('toggle', function() {
      localStorage.setItem('glossary', g.open ? 'open' : 'closed');
    });
  </script>
</body>
</html>
HTML
}

check_master() {
    local result
    result=$(mysql "${MYSQL_OPTS[@]}" -h "$MASTER_HOST" -e "
        SELECT CONCAT('server_id=', @@server_id, ' log_bin=', @@log_bin, ' binlog_format=', @@binlog_format);
    " 2>&1) || { MASTER_LEVEL="ERROR"; MASTER_LINE="unreachable: $result"; log "[ERROR] master $MASTER_LINE"; return; }

    local pos file position
    pos=$(mysql "${MYSQL_OPTS[@]}" -h "$MASTER_HOST" -e "SHOW MASTER STATUS" 2>&1)
    file=$(echo "$pos"     | awk '{print $1}')
    position=$(echo "$pos" | awk '{print $2}')

    MASTER_LEVEL="OK"
    MASTER_LINE="$result  file=$file pos=$position"
    log "[OK] master: $MASTER_LINE"
}

check_slave() {
    local status
    status=$(mysql -u root --password= --connect-timeout=5 -h "$SLAVE_HOST" -e "SHOW SLAVE STATUS\G" 2>&1) \
        || { SLAVE_LEVEL="ERROR"; SLAVE_LINE="unreachable: $status"; log "[ERROR] slave $SLAVE_LINE"; return; }

    local io sql lag io_err sql_err
    io=$(echo "$status"      | grep -i 'Slave_IO_Running:'      | awk '{print $2}')
    sql=$(echo "$status"     | grep -i 'Slave_SQL_Running:'     | awk '{print $2}')
    lag=$(echo "$status"     | grep -i 'Seconds_Behind_Master:' | awk '{print $2}')
    io_err=$(echo "$status"  | grep -i 'Last_IO_Error:'         | sed 's/.*Last_IO_Error: //')
    sql_err=$(echo "$status" | grep -i 'Last_SQL_Error:'        | sed 's/.*Last_SQL_Error: //')

    SLAVE_LEVEL="OK"
    [[ "$lag" != "0" && "$lag" != "NULL" ]] && SLAVE_LEVEL="WARN"
    [[ "$io" != "Yes" || "$sql" != "Yes" ]] && SLAVE_LEVEL="ERROR"

    SLAVE_LINE="io=$io  sql=$sql  lag=${lag}s${io_err:+  io_err=$io_err}${sql_err:+  sql_err=$sql_err}"
    log "[$SLAVE_LEVEL] slave: $SLAVE_LINE"
}

mkdir -p /var/www
log "[INFO] db-monitor started (interval=${INTERVAL}s)"

while true; do
    MASTER_LEVEL="ERROR" MASTER_LINE="not checked"
    SLAVE_LEVEL="ERROR"  SLAVE_LINE="not checked"

    check_master
    check_slave
    write_html "$MASTER_LEVEL" "$MASTER_LINE" "$SLAVE_LEVEL" "$SLAVE_LINE"

    sleep "$INTERVAL"
done
