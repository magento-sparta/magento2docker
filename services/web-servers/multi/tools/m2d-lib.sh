#!/bin/bash
# m2d-lib.sh — shared shell utilities for magento2docker tools
# Source this file; do not execute directly.
#
# ── detect_php <project_root> ────────────────────────────────────────────────
# Resolves the PHP binary for a Magento project directory.
#
# Detection order:
#   1. meta.json `php` key          — full path, written by m2install
#   2. meta.json `php_version` key  — "php8.3" format, written by prepend.php
#   3. phpXX.code.tgz in project root
#   4. M2D_WEB_SERVER_PHP_VERSION env var
#   5. system `php` in PATH
#
# Sets in calling scope:
#   PHP_BIN           full path to php binary       e.g. /usr/local/bin/php83
#   PHP_SEGMENT       URL-safe version segment       e.g. php83
#   PHP_VERSION       dotted version string          e.g. 8.3
#   PHP_DETECTED_FROM source label:
#                       meta_php | meta_php_version | code_tgz |
#                       env_default | system_default

detect_php() {
    local project_root="${1:-$(pwd)}"
    PHP_BIN=""
    PHP_SEGMENT=""
    PHP_VERSION=""
    PHP_DETECTED_FROM=""

    # 1 + 2. meta.json — try `php` key (full path) then `php_version` key ("php8.3")
    if [[ -f "${project_root}/meta.json" ]]; then
        local _result _src _bin
        _result=$(python3 - "${project_root}/meta.json" 2>/dev/null <<'PYEOF'
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get('php', '')
    if v and v.startswith('/'):
        print('meta_php\t' + v)
    else:
        v2 = d.get('php_version', '')
        m = re.match(r'php(\d+)\.(\d+)', v2)
        if m:
            print('meta_php_version\t/usr/local/bin/php' + m.group(1) + m.group(2))
except Exception:
    pass
PYEOF
        )
        if [[ -n "$_result" ]]; then
            IFS=$'\t' read -r _src _bin <<< "$_result"
            if [[ -x "$_bin" ]]; then
                PHP_BIN="$_bin"
                PHP_DETECTED_FROM="$_src"
            fi
        fi
    fi

    # 3. phpXX.code.tgz in project root
    if [[ -z "$PHP_BIN" ]]; then
        local _tgz _ver _candidate
        _tgz=$(find "$project_root" -maxdepth 1 -name 'php[0-9][0-9].code.tgz' 2>/dev/null | head -1)
        if [[ -n "$_tgz" ]]; then
            _ver=$(basename "$_tgz" | sed 's/php\([0-9][0-9]\)\.code\.tgz/\1/')
            _candidate="/usr/local/bin/php${_ver}"
            if [[ -x "$_candidate" ]]; then
                PHP_BIN="$_candidate"
                PHP_DETECTED_FROM="code_tgz"
            fi
        fi
    fi

    # 4. M2D_WEB_SERVER_PHP_VERSION environment variable
    if [[ -z "$PHP_BIN" && -n "${M2D_WEB_SERVER_PHP_VERSION:-}" ]]; then
        local _candidate="/usr/local/bin/php$(echo "$M2D_WEB_SERVER_PHP_VERSION" | tr -d '.')"
        if [[ -x "$_candidate" ]]; then
            PHP_BIN="$_candidate"
            PHP_DETECTED_FROM="env_default"
        fi
    fi

    # 5. System default
    if [[ -z "$PHP_BIN" ]]; then
        PHP_BIN=$(command -v php 2>/dev/null || echo "/usr/bin/php")
        PHP_DETECTED_FROM="system_default"
    fi

    # Derive PHP_SEGMENT and PHP_VERSION from the resolved binary
    PHP_SEGMENT=$("$PHP_BIN" -r 'echo "php".PHP_MAJOR_VERSION.PHP_MINOR_VERSION;' 2>/dev/null || true)
    PHP_VERSION=$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)

    # Final fallback when binary exists but won't run
    if [[ -z "$PHP_SEGMENT" ]]; then
        local _default="${M2D_WEB_SERVER_PHP_VERSION:-8.3}"
        PHP_SEGMENT="php$(echo "$_default" | tr -d '.')"
        PHP_VERSION="$_default"
    fi
}

# ── run_as_magento <cmd> [args…] ─────────────────────────────────────────────
# Run a command as the magento user when we are root and the user exists.
# Falls back to running directly when already running as magento or when the
# magento user is not present (e.g. outside the container).
#
# Usage:
#   run_as_magento yarn install
#   run_as_magento "$PHP_BIN" bin/magento cache:flush
run_as_magento() {
    if [[ "$(id -u)" -eq 0 ]] && id magento &>/dev/null 2>&1; then
        sudo -u magento "$@"
    else
        "$@"
    fi
}
