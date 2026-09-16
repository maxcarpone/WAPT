#!/bin/bash
set -u

SCRIPT_VERSION="0.3"
EXPECTED_DEBIAN_MAJOR="10"
EXPECTED_WAPT_PREFIX="1.8.2.7393"
WAPT_CONFIG="/opt/wapt/conf/waptserver.ini"

ok()      { echo "[ OK ] $*"; }
warn()    { echo "[WARN] $*"; }
block()   { echo "[BLOCK] $*"; BLOCKING=$((BLOCKING + 1)); }

BLOCKING=0

echo "WAPT Server Buster migration precheck v${SCRIPT_VERSION}"
echo "====================================================="
echo

if [ "$(id -u)" -eq 0 ]; then
    ok "Running as root"
else
    block "Must be run as root"
fi

if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "OS: ${PRETTY_NAME:-unknown}"
    if [ "${VERSION_ID:-}" = "$EXPECTED_DEBIAN_MAJOR" ]; then
        ok "Debian ${EXPECTED_DEBIAN_MAJOR}"
    else
        block "Expected Debian ${EXPECTED_DEBIAN_MAJOR}, found ${VERSION_ID:-unknown}"
    fi
else
    block "/etc/os-release unavailable"
fi

WAPT_VERSION="$(dpkg-query -W -f='${Version}' tis-waptserver 2>/dev/null || true)"
echo "tis-waptserver: ${WAPT_VERSION:-not installed}"

case "$WAPT_VERSION" in
    ${EXPECTED_WAPT_PREFIX}*)
        ok "Expected WAPT 7393 source version"
        ;;
    "")
        block "tis-waptserver is not installed"
        ;;
    *)
        block "Unexpected WAPT server version: $WAPT_VERSION"
        ;;
esac

if [ -x /opt/wapt/bin/python ]; then
    PYTHON_VERSION="$(/opt/wapt/bin/python --version 2>&1)"
    echo "WAPT Python: $PYTHON_VERSION"
else
    block "/opt/wapt/bin/python missing"
fi

for service in waptserver wapttasks nginx; do
    if systemctl is-active --quiet "$service"; then
        ok "Service $service active"
    else
        block "Service $service is not active"
    fi
done

if [ -f "$WAPT_CONFIG" ]; then
    ok "Configuration found: $WAPT_CONFIG"
    echo "Config SHA256: $(sha256sum "$WAPT_CONFIG" | awk '{print $1}')"
else
    block "Configuration missing: $WAPT_CONFIG"
fi

for cmd in pg_dump pg_restore psql sha256sum tar openssl apt-get dpkg-query; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Tool available: $cmd"
    else
        block "Required tool missing: $cmd"
    fi
done

# PostgreSQL / WAPT database detection
if command -v pg_lsclusters >/dev/null 2>&1; then
    ok "Tool available: pg_lsclusters"

    WAPT_DB_COUNT=0
    WAPT_DB_PORT=""
    WAPT_DB_VERSION=""

    while read -r pg_version pg_cluster pg_port pg_status pg_owner rest; do
        [ "$pg_status" = "online" ] || continue

        if sudo -u postgres psql -p "$pg_port" -Atc \
            "SELECT 1 FROM pg_database WHERE datname='wapt';" 2>/dev/null \
            | grep -qx '1'; then
            WAPT_DB_COUNT=$((WAPT_DB_COUNT + 1))
            WAPT_DB_PORT="$pg_port"
            WAPT_DB_VERSION="$pg_version"
        fi
    done < <(pg_lsclusters --no-header)

    case "$WAPT_DB_COUNT" in
        1)
            ok "WAPT database found on PostgreSQL ${WAPT_DB_VERSION}, port ${WAPT_DB_PORT}"
            ;;
        0)
            block "No WAPT database found on any online PostgreSQL cluster"
            ;;
        *)
            block "WAPT database found on multiple PostgreSQL clusters"
            ;;
    esac
else
    block "Required tool missing: pg_lsclusters"
fi

# WAPT database compatibility and baseline fingerprint
if [ "${WAPT_DB_COUNT:-0}" -eq 1 ]; then
    DB_VERSION="$(sudo -u postgres psql -p "$WAPT_DB_PORT" -d wapt -Atc \
        "SELECT value::text FROM serverattribs WHERE key='db_version';" \
        2>/dev/null || true)"

    if [ "$DB_VERSION" = '"1.8.2.1"' ]; then
        ok "WAPT database schema version: ${DB_VERSION}"
    elif [ -z "$DB_VERSION" ]; then
        block "Unable to read WAPT database schema version"
    else
        block "Unexpected WAPT database schema version: ${DB_VERSION}"
    fi

    echo "Database baseline:"
    for table in \
        hostgroups \
        hostpackagesstatus \
        hosts \
        hostsoftwares \
        packages \
        waptusers
    do
        count="$(sudo -u postgres psql -p "$WAPT_DB_PORT" -d wapt -Atc \
            "SELECT count(*) FROM ${table};" 2>/dev/null || true)"

        if [[ "$count" =~ ^[0-9]+$ ]]; then
            echo "  ${table}=${count}"
        else
            block "Unable to count table: ${table}"
        fi
    done
fi

echo
echo "====================================================="
if [ "$BLOCKING" -eq 0 ]; then
    echo "PRECHECK RESULT: PASS"
    exit 0
else
    echo "PRECHECK RESULT: BLOCKED ($BLOCKING blocking issue(s))"
    exit 1
fi
