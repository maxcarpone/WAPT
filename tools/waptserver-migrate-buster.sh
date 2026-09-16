#!/bin/bash
set -u

SCRIPT_VERSION="0.4"
EXPECTED_DEBIAN_MAJOR="10"
EXPECTED_WAPT_PREFIX="1.8.2.7393"
WAPT_CONFIG="/opt/wapt/conf/waptserver.ini"
BACKUP_ROOT="/var/www/wapt-backups"

ok()    { echo "[ OK ] $*"; }
warn()  { echo "[WARN] $*"; }
block() { echo "[BLOCK] $*"; BLOCKING=$((BLOCKING + 1)); }

BLOCKING=0
WAPT_DB_COUNT=0
WAPT_DB_PORT=""
WAPT_DB_VERSION=""
DB_VERSION=""
CONFIG_SHA256=""

declare -A DB_COUNTS

precheck() {
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
        PYTHON_VERSION=""
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
        CONFIG_SHA256="$(sha256sum "$WAPT_CONFIG" | awk '{print $1}')"
        echo "Config SHA256: $CONFIG_SHA256"
    else
        block "Configuration missing: $WAPT_CONFIG"
    fi

    for cmd in pg_dump pg_restore psql sha256sum tar openssl apt-get \
               dpkg-query runuser stat df hostname; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "Tool available: $cmd"
        else
            block "Required tool missing: $cmd"
        fi
    done

    if command -v pg_lsclusters >/dev/null 2>&1; then
        ok "Tool available: pg_lsclusters"

        WAPT_DB_COUNT=0
        WAPT_DB_PORT=""
        WAPT_DB_VERSION=""

        while read -r pg_version pg_cluster pg_port pg_status pg_owner rest; do
            [ "$pg_status" = "online" ] || continue

            if runuser -u postgres -- psql -p "$pg_port" -Atc \
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

    if [ "$WAPT_DB_COUNT" -eq 1 ]; then
        DB_VERSION="$(runuser -u postgres -- psql -p "$WAPT_DB_PORT" -d wapt -Atc \
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
            count="$(runuser -u postgres -- psql -p "$WAPT_DB_PORT" -d wapt -Atc \
                "SELECT count(*) FROM ${table};" 2>/dev/null || true)"

            if [[ "$count" =~ ^[0-9]+$ ]]; then
                DB_COUNTS["$table"]="$count"
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
        return 0
    else
        echo "PRECHECK RESULT: BLOCKED ($BLOCKING blocking issue(s))"
        return 1
    fi
}

backup() {
    precheck || {
        echo
        echo "BACKUP RESULT: BLOCKED (precheck failed)"
        return 1
    }

    echo
    echo "WAPT Server Buster migration backup v${SCRIPT_VERSION}"
    echo "====================================================="

    TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
    HOST="$(hostname)"
    BACKUP_DIR="${BACKUP_ROOT}/migration-7393-7398-${TIMESTAMP}"
    DB_DUMP="${BACKUP_DIR}/wapt-${HOST}.dump"
    CONFIG_ARCHIVE="${BACKUP_DIR}/wapt-config-${HOST}.tar.gz"
    MANIFEST="${BACKUP_DIR}/manifest.txt"
    CHECKSUMS="${BACKUP_DIR}/SHA256SUMS"

    # Conservative space requirement:
    # twice the active PostgreSQL cluster size + 1 GiB.
    PG_DATA_DIR="$(pg_lsclusters --no-header | awk \
        -v port="$WAPT_DB_PORT" '$3 == port {print $6; exit}')"

    if [ -z "$PG_DATA_DIR" ] || [ ! -d "$PG_DATA_DIR" ]; then
        block "Unable to determine PostgreSQL data directory"
        echo "BACKUP RESULT: BLOCKED"
        return 1
    fi

    PG_SIZE_BYTES="$(du -sb "$PG_DATA_DIR" 2>/dev/null | awk '{print $1}')"
    FREE_BYTES="$(df -B1 --output=avail "$BACKUP_ROOT" 2>/dev/null | tail -1 | tr -d ' ')"

    # BACKUP_ROOT may not exist yet; inspect /var/www in that case.
    if ! [[ "$FREE_BYTES" =~ ^[0-9]+$ ]]; then
        FREE_BYTES="$(df -B1 --output=avail /var/www | tail -1 | tr -d ' ')"
    fi

    if ! [[ "$PG_SIZE_BYTES" =~ ^[0-9]+$ ]] || \
       ! [[ "$FREE_BYTES" =~ ^[0-9]+$ ]]; then
        block "Unable to determine backup space requirements"
        echo "BACKUP RESULT: BLOCKED"
        return 1
    fi

    REQUIRED_BYTES=$((PG_SIZE_BYTES * 2 + 1073741824))

    echo "PostgreSQL data size: ${PG_SIZE_BYTES} bytes"
    echo "Backup filesystem free: ${FREE_BYTES} bytes"
    echo "Required safety space: ${REQUIRED_BYTES} bytes"

    if [ "$FREE_BYTES" -lt "$REQUIRED_BYTES" ]; then
        block "Insufficient free space for verified backup"
        echo "BACKUP RESULT: BLOCKED"
        return 1
    fi
    ok "Sufficient free space"

    mkdir -p "$BACKUP_DIR" || {
        block "Unable to create $BACKUP_DIR"
        return 1
    }
    chmod 700 "$BACKUP_DIR"

    echo
    echo "Creating PostgreSQL custom-format dump..."
    if (cd /tmp && runuser -u postgres -- pg_dump -p "$WAPT_DB_PORT" -Fc -d wapt) > "$DB_DUMP"; then
        ok "Database dump created"
    else
        block "Database dump failed"
        return 1
    fi

    if [ ! -s "$DB_DUMP" ]; then
        block "Database dump is empty"
        return 1
    fi

    if pg_restore -l "$DB_DUMP" >/dev/null 2>&1; then
        ok "Database dump verified with pg_restore -l"
    else
        block "Database dump verification failed"
        return 1
    fi

    echo
    echo "Creating configuration archive..."

    BACKUP_PATHS=()
    for path in \
        /opt/wapt/conf \
        /opt/wapt/waptserver/ssl \
        /etc/nginx/sites-available/wapt.conf \
        /var/www/ssl
    do
        if [ -e "$path" ]; then
            BACKUP_PATHS+=("${path#/}")
        else
            warn "Optional backup path missing: $path"
        fi
    done

    if [ "${#BACKUP_PATHS[@]}" -eq 0 ]; then
        block "No configuration paths available for backup"
        return 1
    fi

    if tar -C / -czf "$CONFIG_ARCHIVE" "${BACKUP_PATHS[@]}"; then
        ok "Configuration archive created"
    else
        block "Configuration archive failed"
        return 1
    fi

    if tar -tzf "$CONFIG_ARCHIVE" >/dev/null 2>&1; then
        ok "Configuration archive verified"
    else
        block "Configuration archive verification failed"
        return 1
    fi

    {
        echo "script_version=${SCRIPT_VERSION}"
        echo "timestamp=${TIMESTAMP}"
        echo "hostname=${HOST}"
        echo "os=${PRETTY_NAME:-unknown}"
        echo "kernel=$(uname -r)"
        echo "wapt_version=${WAPT_VERSION}"
        echo "wapt_python=${PYTHON_VERSION}"
        echo "config_path=${WAPT_CONFIG}"
        echo "config_sha256=${CONFIG_SHA256}"
        echo "postgresql_version=${WAPT_DB_VERSION}"
        echo "postgresql_port=${WAPT_DB_PORT}"
        echo "postgresql_data_dir=${PG_DATA_DIR}"
        echo "postgresql_data_size_bytes=${PG_SIZE_BYTES}"
        echo "db_version=${DB_VERSION}"
        for table in \
            hostgroups \
            hostpackagesstatus \
            hosts \
            hostsoftwares \
            packages \
            waptusers
        do
            echo "${table}=${DB_COUNTS[$table]}"
        done
    } > "$MANIFEST"

    (
        cd "$BACKUP_DIR" || exit 1
        sha256sum "$(basename "$DB_DUMP")" \
                  "$(basename "$CONFIG_ARCHIVE")" \
                  "$(basename "$MANIFEST")" > "$(basename "$CHECKSUMS")"
    ) || {
        block "Unable to generate SHA256SUMS"
        return 1
    }

    if (cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS); then
        ok "Backup checksums verified"
    else
        block "Backup checksum verification failed"
        return 1
    fi

    chmod 600 "$DB_DUMP" "$CONFIG_ARCHIVE" "$MANIFEST" "$CHECKSUMS"

    echo
    echo "Backup directory: $BACKUP_DIR"
    echo "Database dump: $(basename "$DB_DUMP")"
    echo "Configuration archive: $(basename "$CONFIG_ARCHIVE")"
    echo "Manifest: $(basename "$MANIFEST")"
    echo "Checksums: $(basename "$CHECKSUMS")"
    echo
    echo "====================================================="
    echo "BACKUP RESULT: PASS"
}

usage() {
    echo "Usage: $0 {precheck|backup}"
}

case "${1:-precheck}" in
    precheck)
        precheck
        ;;
    backup)
        backup
        ;;
    *)
        usage
        exit 2
        ;;
esac
