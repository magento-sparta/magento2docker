#!/usr/bin/env bash

# ── Check M2D_APACHE_ROOT_DIRECTORY ──────────────────────────────────────────
if [ -z "${M2D_APACHE_ROOT_DIRECTORY}" ]; then
    echo "[m2install] ERROR: M2D_APACHE_ROOT_DIRECTORY is not set" >&2
    exit 1
fi

# ── Validate and resolve project root from current path ──────────────────────
CWD=$(pwd)
APACHE_ROOT="${M2D_APACHE_ROOT_DIRECTORY%/}"  # strip trailing slash

# Must be inside M2D_APACHE_ROOT_DIRECTORY
if [[ "${CWD}" != "${APACHE_ROOT}/"* ]]; then
    echo "[m2install] ERROR: Current path '${CWD}' is not inside M2D_APACHE_ROOT_DIRECTORY '${APACHE_ROOT}'" >&2
    exit 1
fi

# Must not be M2D_APACHE_ROOT_DIRECTORY itself
if [ "${CWD}" = "${APACHE_ROOT}" ]; then
    echo "[m2install] ERROR: Current path must not be M2D_APACHE_ROOT_DIRECTORY itself ('${APACHE_ROOT}')" >&2
    exit 1
fi

# Resolve project root: first path component after APACHE_ROOT
RELATIVE="${CWD#${APACHE_ROOT}/}"
PROJECT_NAME="${RELATIVE%%/*}"
PROJECT_ROOT="${APACHE_ROOT}/${PROJECT_NAME}"

if [ "${CWD}" != "${PROJECT_ROOT}" ]; then
    echo "[m2install] Changing directory from '${CWD}' to project root '${PROJECT_ROOT}'"
    cd "${PROJECT_ROOT}" || { echo "[m2install] ERROR: Cannot cd to '${PROJECT_ROOT}'" >&2; exit 1; }
fi

# ── Pre-scan args: honour explicit flags before auto-detecting ────────────────
EXPLICIT_PHP=""
EXPLICIT_SOURCE=""
EXPLICIT_ES_HOST=""
EXPLICIT_ES_PORT=""
_prev=""
for _arg in "$@"; do
    case "$_prev" in
        --php)                          EXPLICIT_PHP="$_arg"     ;;
        -s|--source)                    EXPLICIT_SOURCE="$_arg"  ;;
        --es-host|--elasticsearch-host) EXPLICIT_ES_HOST="$_arg" ;;
        --es-port|--elasticsearch-port) EXPLICIT_ES_PORT="$_arg" ;;
    esac
    _prev="$_arg"
done
unset _prev _arg

# ── Detect PHP version ────────────────────────────────────────────────────────
source /usr/local/bin/m2d-lib.sh

# Always run auto-detection first so .m2install.conf (written by a previous
# successful install) can take priority over any --php injected by wrappers
# like _call_m2install.  The explicit CLI flag is only honoured when the
# project has no stored PHP preference (env_default / system_default), i.e.
# on a fresh install where .m2install.conf does not yet have M2D_PHP_BIN.
detect_php "$PROJECT_ROOT"

if [[ -n "$EXPLICIT_PHP" && "$PHP_DETECTED_FROM" =~ ^(env_default|system_default)$ ]]; then
    # No project-specific PHP found — resolve the caller's explicit value.
    # Accepts: full path (/usr/local/bin/php84), short name (php84), "php8.4" style.
    if [[ -x "$EXPLICIT_PHP" ]]; then
        PHP_BIN="$EXPLICIT_PHP"
    elif [[ -x "/usr/local/bin/${EXPLICIT_PHP}" ]]; then
        PHP_BIN="/usr/local/bin/${EXPLICIT_PHP}"
    else
        PHP_BIN=$(command -v "$EXPLICIT_PHP" 2>/dev/null || true)
    fi
    if [[ -z "$PHP_BIN" ]]; then
        echo "[m2install] ERROR: Cannot resolve --php '${EXPLICIT_PHP}' to an executable." >&2
        echo "[m2install]        Available: $(ls /usr/local/bin/php?? 2>/dev/null | xargs -I{} basename {} | tr '\n' ' ')" >&2
        exit 1
    fi
    PHP_DETECTED_FROM="cli_flag"
    PHP_SEGMENT=$("$PHP_BIN" -r 'echo "php".PHP_MAJOR_VERSION.PHP_MINOR_VERSION;' 2>/dev/null || true)
    PHP_VERSION=$("$PHP_BIN"  -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'  2>/dev/null || true)
fi

# ── Detect install source (git clone vs composer project) ────────────────────
# Priority:
#   1. explicit -s / --source flag
#   2. php*.code.tgz present → composer (Magento Cloud / packaged archive)
#   3. .git/ present → git
#   4. composer.lock present → composer
#   5. default → composer
_tgz=$(ls "${PROJECT_ROOT}"/php*.code.tgz 2>/dev/null | head -1 || true)

if [[ -n "$EXPLICIT_SOURCE" ]]; then
    DETECTED_SOURCE="$EXPLICIT_SOURCE"
elif [[ -n "$_tgz" ]]; then
    DETECTED_SOURCE="composer"
elif [[ -d "${PROJECT_ROOT}/.git" ]]; then
    DETECTED_SOURCE="git"
elif [[ -f "${PROJECT_ROOT}/composer.lock" ]]; then
    DETECTED_SOURCE="composer"
else
    DETECTED_SOURCE="composer"
fi

# ── Print php + source (combined when both come from the same tgz) ────────────
if [[ "$PHP_DETECTED_FROM" == "code_tgz" && -n "$_tgz" && -z "$EXPLICIT_SOURCE" ]]; then
    echo "[m2install] php: $PHP_BIN ($PHP_VERSION)  source: composer  [$(basename "$_tgz")]"
else
    echo "[m2install] php: $PHP_BIN ($PHP_VERSION) [source: $PHP_DETECTED_FROM]"
    if [[ -n "$EXPLICIT_SOURCE" ]]; then
        echo "[m2install] source: ${DETECTED_SOURCE} [cli_flag]"
    elif [[ -n "$_tgz" ]]; then
        echo "[m2install] source: composer [$(basename "$_tgz")]"
    elif [[ "$DETECTED_SOURCE" == "git" ]]; then
        echo "[m2install] source: git [.git/]"
    elif [[ -f "${PROJECT_ROOT}/composer.lock" ]]; then
        echo "[m2install] source: composer [composer.lock]"
    else
        echo "[m2install] source: composer [default]"
    fi
fi

# ── Intercept --php from args and replace with detected PHP ──────────────────
NEW_ARGS=()
while [ $# -gt 0 ]; do
    if [ "$1" = "--php" ]; then
        shift 2 2>/dev/null || shift   # drop --php and its value
    else
        NEW_ARGS+=("$1")
        shift
    fi
done
set -- "--php" "${PHP_BIN}" "${NEW_ARGS[@]}"

export BIN_PHP="${PHP_BIN}"

# ── Write initial .m2install.conf (HTTP_HOST only) ───────────────────────────
# Written before _m2install.sh so loadConfigFile picks up the correct BASE URL.
# Metadata keys (M2D_*) are appended after a successful install — .prepend.php
# uses their presence as a signal that the project is fully installed.
echo "HTTP_HOST=https://${PROJECT_NAME}.${PHP_SEGMENT}.127.0.0.1.nip.io/" > .m2install.conf
[[ -n "$DETECTED_SOURCE" ]] && echo "SOURCE=${DETECTED_SOURCE}" >> .m2install.conf

# ── Remove auto-seeded prepend files ─────────────────────────────────────────
# .prepend.php is seeded by auto_prepend_file on the first PHP CLI call above.
# Remove it now so _m2install.sh sees an empty directory and skips its cleanup
# prompt.  It will be re-seeded by .prepend.php once M2D_PHP_BIN is present.
rm -f .prepend.php .prepend.dist.php

echo "[m2install] Args: $@"

# ── Run _m2install.sh ─────────────────────────────────────────────────────────
bash /usr/local/bin/_m2install.sh "$@"
_M2INSTALL_EXIT=$?

# ── Write post-install metadata to .m2install.conf ───────────────────────────
# Appended only on success.  .prepend.php checks for M2D_PHP_BIN to decide
# whether the project is installed before seeding itself into the project root.
if [[ $_M2INSTALL_EXIT -eq 0 ]]; then
    {
        echo "M2D_PHP_BIN=${PHP_BIN}"
        echo "M2D_PHP_VERSION=${PHP_VERSION}"
        [[ -n "$EXPLICIT_ES_HOST" ]] && echo "M2D_SEARCH_ENGINE_HOST=${EXPLICIT_ES_HOST}"
        [[ -n "$EXPLICIT_ES_PORT" ]] && echo "M2D_SEARCH_ENGINE_PORT=${EXPLICIT_ES_PORT}"
    } >> .m2install.conf
    echo "[m2install] Written post-install metadata to .m2install.conf"
fi

exit $_M2INSTALL_EXIT
