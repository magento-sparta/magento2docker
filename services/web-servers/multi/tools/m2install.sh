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

# ── Detect PHP version ────────────────────────────────────────────────────────
source /usr/local/bin/m2d-lib.sh
detect_php "$PROJECT_ROOT"
echo "[m2install] php: $PHP_BIN ($PHP_VERSION) [source: $PHP_DETECTED_FROM]"

# When found from .code.tgz, cache the path in meta.json for faster future runs
if [[ "$PHP_DETECTED_FROM" == "code_tgz" ]]; then
    python3 - "${PROJECT_ROOT}/meta.json" "$PHP_BIN" <<'PYEOF'
import json, os, sys
path, php_path = sys.argv[1], sys.argv[2]
data = {}
if os.path.isfile(path):
    with open(path) as f:
        try: data = json.load(f)
        except Exception: pass
data['php'] = php_path
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
print('[m2install] Written php to meta.json')
PYEOF
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

# ── Detect install source (git clone vs composer project) ────────────────────
# Written to .m2install.conf so _m2install.sh picks it up automatically
# (loadConfigFile sources the file) — no --source flag needed on future runs.
if [[ -d "${PROJECT_ROOT}/.git" ]]; then
    DETECTED_SOURCE="git"
    echo "[m2install] source: git (found .git/)"
elif [[ -f "${PROJECT_ROOT}/composer.lock" ]]; then
    DETECTED_SOURCE="composer"
    echo "[m2install] source: composer (found composer.lock, no .git/)"
else
    DETECTED_SOURCE=""
    echo "[m2install] source: unknown (no .git/ or composer.lock found)"
fi

# ── Write .m2install.conf ─────────────────────────────────────────────────────
{
    echo "HTTP_HOST=https://${PROJECT_NAME}.${PHP_SEGMENT}.127.0.0.1.nip.io/"
    [[ -n "$DETECTED_SOURCE" ]] && echo "SOURCE=${DETECTED_SOURCE}"
} > .m2install.conf

echo "[m2install] Written .m2install.conf: HTTP_HOST=https://${PROJECT_NAME}.${PHP_SEGMENT}.127.0.0.1.nip.io/"
echo "[m2install] Args: $@"

source /usr/local/bin/_m2install.sh "$@"
