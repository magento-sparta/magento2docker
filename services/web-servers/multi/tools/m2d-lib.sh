#!/bin/bash
# m2d-lib.sh — shared shell utilities for magento2docker tools
# Source this file; do not execute directly.
#
# ── detect_php <project_root> ────────────────────────────────────────────────
# Resolves the PHP binary for a Magento project directory.
#
# Detection order:
#   1. .m2install.conf `M2D_PHP_BIN` key — full path, written by m2install on success
#   2. phpXX.code.tgz in project root
#   3. M2D_WEB_SERVER_PHP_VERSION env var
#   4. system `php` in PATH
#
# Sets in calling scope:
#   PHP_BIN           full path to php binary       e.g. /usr/local/bin/php83
#   PHP_SEGMENT       URL-safe version segment       e.g. php83
#   PHP_VERSION       dotted version string          e.g. 8.3
#   PHP_DETECTED_FROM source label:
#                       m2install_conf | code_tgz | env_default | system_default

detect_php() {
    local project_root="${1:-$(pwd)}"
    PHP_BIN=""
    PHP_SEGMENT=""
    PHP_VERSION=""
    PHP_DETECTED_FROM=""

    # 1. .m2install.conf — M2D_PHP_BIN key (written by m2install on successful install)
    if [[ -f "${project_root}/.m2install.conf" ]]; then
        local _bin
        _bin=$(grep -m1 '^M2D_PHP_BIN=' "${project_root}/.m2install.conf" | cut -d= -f2-)
        if [[ -n "$_bin" && -x "$_bin" ]]; then
            PHP_BIN="$_bin"
            PHP_DETECTED_FROM="m2install_conf"
        fi
    fi

    # 2. phpXX.code.tgz in project root
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

    # 3. M2D_WEB_SERVER_PHP_VERSION environment variable
    if [[ -z "$PHP_BIN" && -n "${M2D_WEB_SERVER_PHP_VERSION:-}" ]]; then
        local _candidate="/usr/local/bin/php$(echo "$M2D_WEB_SERVER_PHP_VERSION" | tr -d '.')"
        if [[ -x "$_candidate" ]]; then
            PHP_BIN="$_candidate"
            PHP_DETECTED_FROM="env_default"
        fi
    fi

    # 4. System default
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

# ── PWA multi-store helpers ────────────────────────────────────────────────────

# pwa_meta_file APACHE_ROOT PROJECT [STORE_CODE]
# Returns path to .pwa (default store) or .pwa.<store> (named store).
pwa_meta_file() {
    local root="$1" project="$2" store="${3:-}"
    [[ -n "$store" ]] && echo "${root}/${project}/.pwa.${store}" || echo "${root}/${project}/.pwa"
}

# pwa_run_key PROJECT [STORE_CODE]
# Key used for Apache RewriteMap, PID file, log file.
# Default store: "<project>"   Named store: "<project>-<store>"
pwa_run_key() {
    local project="$1" store="${2:-}"
    [[ -n "$store" ]] && echo "${project}-${store}" || echo "${project}"
}

# pwa_default_dir APACHE_ROOT PROJECT [STORE_CODE]
# Default PWA directory.  Default: "<project>/pwa"  Named: "<project>/pwa-<store>"
pwa_default_dir() {
    local root="$1" project="$2" store="${3:-}"
    [[ -n "$store" ]] && echo "${root}/${project}/pwa-${store}" || echo "${root}/${project}/pwa"
}

# pwa_dev_url RUN_KEY PHP_SEGMENT
# Returns https://pwa-<run_key>.<phpver>.127.0.0.1.nip.io/
pwa_dev_url() {
    echo "https://pwa-${1}.${2}.127.0.0.1.nip.io/"
}
