#!/bin/bash
set -u

SCRIPT_VERSION="0.4.4"

ok()   { echo "[ OK ] $*"; }
warn() { echo "[WARN] $*" >&2; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

create_target_safety_backup() {
    SAFETY_ROOT="/var/www/wapt-backups"
    SAFETY_STAMP="$(date +%Y%m%d-%H%M%S)"
    SAFETY_NAME="wapt-target-safety-${HOSTNAME:-unknown}-${SAFETY_STAMP}"
    SAFETY_WORK="$(mktemp -d "${SAFETY_ROOT}/.${SAFETY_NAME}.XXXXXX")" || \
        fail "Unable to create target safety-backup staging directory"
    SAFETY_ARCHIVE="${SAFETY_ROOT}/${SAFETY_NAME}.tar"

    chmod 0700 "$SAFETY_WORK" || fail "Unable to secure safety-backup staging directory"
    mkdir -p \
        "$SAFETY_WORK/database" \
        "$SAFETY_WORK/config" \
        "$SAFETY_WORK/metadata" \
        "$SAFETY_WORK/package-owned"
    chmod 0700 \
        "$SAFETY_WORK/database" \
        "$SAFETY_WORK/config" \
        "$SAFETY_WORK/metadata" \
        "$SAFETY_WORK/package-owned"

    echo "Creating lightweight target safety backup..."
    echo "Repository payload is intentionally NOT copied."

    (cd / && runuser -u postgres -- \
        pg_dump -p "$TARGET_PG_PORT" -Fc wapt) > "$SAFETY_WORK/database/wapt.dump" || \
        fail "Target safety database dump failed"
    [ -s "$SAFETY_WORK/database/wapt.dump" ] || fail "Target safety database dump is empty"
    pg_restore -l "$SAFETY_WORK/database/wapt.dump" >/dev/null 2>&1 || \
        fail "Target safety database dump is not readable"

    if [ -d /opt/wapt/conf ]; then
        tar -C / -cf "$SAFETY_WORK/config/opt-wapt-conf.tar" opt/wapt/conf || \
            fail "Unable to save target /opt/wapt/conf"
    fi
    if [ -d /opt/wapt/waptserver/ssl ]; then
        tar -C / -cf "$SAFETY_WORK/config/server-tls.tar" opt/wapt/waptserver/ssl || \
            fail "Unable to save target server TLS directory"
    fi
    if [ -f /etc/nginx/sites-available/wapt.conf ]; then
        cp -a /etc/nginx/sites-available/wapt.conf "$SAFETY_WORK/config/nginx-wapt.conf" || \
            fail "Unable to save target nginx WAPT configuration"
    elif [ -f /etc/nginx/sites-enabled/wapt.conf ]; then
        cp -a /etc/nginx/sites-enabled/wapt.conf "$SAFETY_WORK/config/nginx-wapt.conf" || \
            fail "Unable to save target nginx WAPT configuration"
    fi

    for f in /var/www/wapt/waptsetup-tis.exe /var/www/wapt/waptdeploy.exe; do
        if [ -f "$f" ]; then
            cp -a "$f" "$SAFETY_WORK/package-owned/" || \
                fail "Unable to save target package-owned artifact: $f"
        fi
    done

    {
        echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "hostname=${HOSTNAME:-unknown}"
        echo "debian=${TARGET_DEBIAN}"
        echo "waptserver=${TARGET_WAPT}"
        echo "waptsetup=${TARGET_SETUP}"
        echo "postgresql=${TARGET_PG_VERSION}"
        echo "pg_cluster=${TARGET_PG_MAJOR}/${TARGET_PG_CLUSTER}"
        echo "pg_port=${TARGET_PG_PORT}"
        echo "db_owner=${TARGET_DB_OWNER}"
        echo "db_marker=${TARGET_DB_MARKER}"
        echo "repository_payload_copied=no"
    } > "$SAFETY_WORK/metadata/target.txt"

    if [ -d /var/www/wapt ]; then
        find /var/www/wapt -type f \
            -printf '%m|%u|%g|%s|%p\n' | sort \
            > "$SAFETY_WORK/metadata/repository-inventory.txt" || \
            fail "Unable to inventory target repository"
    else
        : > "$SAFETY_WORK/metadata/repository-inventory.txt"
    fi

    find "$SAFETY_WORK" -type d -exec chmod 0700 {} + || \
        fail "Unable to secure safety-backup directories"
    find "$SAFETY_WORK" -type f -exec chmod 0600 {} + || \
        fail "Unable to secure safety-backup files"

    tar -C "$SAFETY_ROOT" -cf "$SAFETY_ARCHIVE" "$(basename "$SAFETY_WORK")" || \
        fail "Unable to create target safety-backup archive"
    chmod 0600 "$SAFETY_ARCHIVE" || fail "Unable to secure target safety-backup archive"

    tar -tf "$SAFETY_ARCHIVE" >/dev/null || fail "Target safety-backup archive is not readable"
    tar -xOf "$SAFETY_ARCHIVE" "$(basename "$SAFETY_WORK")/database/wapt.dump" \
        | pg_restore -l >/dev/null 2>&1 || \
        fail "Database dump inside target safety-backup archive is not readable"

    rm -rf -- "$SAFETY_WORK"
    SAFETY_WORK=""

    ok "Target safety backup created and structurally validated"
    echo "Target safety backup: $SAFETY_ARCHIVE"
    echo "NOTE: repository package payload is not included in this safety backup."
}

restore_target_database() {
    echo
    echo "=================================================="
    echo "DESTRUCTIVE DATABASE PHASE"
    echo "=================================================="
    echo "The target WAPT database will now be replaced."
    echo "Safety backup retained at: $SAFETY_ARCHIVE"
    echo

    echo "Stopping WAPT application services..."
    systemctl stop waptserver || fail "Unable to stop waptserver"

    if systemctl cat wapttasks.service >/dev/null 2>&1; then
        systemctl stop wapttasks || fail "Unable to stop wapttasks"
        systemctl is-active --quiet wapttasks && fail "wapttasks is still active"
    fi

    systemctl is-active --quiet waptserver && fail "waptserver is still active"
    systemctl is-active --quiet postgresql || fail "PostgreSQL unexpectedly became inactive"
    ok "WAPT application services stopped; PostgreSQL remains active"

    echo "Replacing target database wapt on PostgreSQL ${TARGET_PG_MAJOR}/${TARGET_PG_CLUSTER}, port ${TARGET_PG_PORT}..."

    (cd / && runuser -u postgres -- \
        dropdb -p "$TARGET_PG_PORT" --if-exists wapt) || \
        fail "Unable to drop target WAPT database"

    (cd / && runuser -u postgres -- \
        createdb -p "$TARGET_PG_PORT" -O wapt -E UTF8 -T template0 wapt) || \
        fail "Unable to recreate target WAPT database"

    (cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -v ON_ERROR_STOP=1 \
        -c 'DROP SCHEMA public;') >/dev/null || \
        fail "Unable to prepare target WAPT database schema"

    cat "$BUNDLE/database/wapt.dump" | \
        (cd / && runuser -u postgres -- \
            pg_restore --exit-on-error --no-owner \
            -p "$TARGET_PG_PORT" -d wapt) || \
        fail "Database restore failed"

    ok "Logical database restore completed"

    echo "Applying targeted WAPT ownership and schema ACL corrections..."

    (cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -v ON_ERROR_STOP=1 <<'SQL'
ALTER DATABASE wapt OWNER TO wapt;
ALTER SCHEMA public OWNER TO wapt;
GRANT USAGE, CREATE ON SCHEMA public TO wapt;

DO $$
DECLARE
    obj record;
BEGIN
    FOR obj IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I OWNER TO wapt',
                       obj.schemaname, obj.tablename);
    END LOOP;

    FOR obj IN
        SELECT sequence_schema, sequence_name
        FROM information_schema.sequences
        WHERE sequence_schema = 'public'
    LOOP
        EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO wapt',
                       obj.sequence_schema, obj.sequence_name);
    END LOOP;
END
$$;
SQL
    ) >/dev/null || fail "Unable to apply WAPT ownership/schema ACL corrections"

    POST_DB_OWNER="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d postgres -Atqc \
        "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='wapt';" \
        2>/dev/null)" || fail "Unable to validate restored database owner"
    [ "$POST_DB_OWNER" = "wapt" ] || \
        fail "Restored WAPT database owner is not wapt: ${POST_DB_OWNER:-missing}"

    POST_SCHEMA_ACL="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT has_schema_privilege('wapt','public','USAGE')::int || '|' || has_schema_privilege('wapt','public','CREATE')::int;" \
        2>/dev/null)" || fail "Unable to validate restored schema privileges"
    [ "$POST_SCHEMA_ACL" = "1|1" ] || \
        fail "Restored public schema privileges for wapt are incomplete: ${POST_SCHEMA_ACL:-missing}"

    NON_WAPT_TABLES="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tableowner <> 'wapt';" \
        2>/dev/null)" || fail "Unable to validate restored table ownership"
    [ "$NON_WAPT_TABLES" = "0" ] || \
        fail "Some restored public tables are not owned by wapt: $NON_WAPT_TABLES"

    NON_WAPT_SEQUENCES="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='S' AND pg_get_userbyid(c.relowner) <> 'wapt';" \
        2>/dev/null)" || fail "Unable to validate restored sequence ownership"
    [ "$NON_WAPT_SEQUENCES" = "0" ] || \
        fail "Some restored public sequences are not owned by wapt: $NON_WAPT_SEQUENCES"

    POST_DB_MARKER="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT value FROM serverattribs WHERE key='db_version';" \
        2>/dev/null)" || fail "Unable to read restored WAPT database marker"
    [ -n "$POST_DB_MARKER" ] || fail "Restored WAPT database marker is empty"
    [ "$POST_DB_MARKER" = "$SOURCE_DB_MARKER" ] || \
        fail "Restored DB marker mismatch: source=$SOURCE_DB_MARKER restored=$POST_DB_MARKER"

    echo
    echo "Restored DB marker: $POST_DB_MARKER"
    echo "Essential restored table counts:"
    for table in hostgroups hostpackagesstatus hosts hostsoftwares packages waptusers; do
        count="$(cd / && runuser -u postgres -- \
            psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
            "SELECT count(*) FROM public.${table};" 2>/dev/null)" || \
            fail "Unable to count restored table: $table"
        printf '  %-20s %s\n' "$table" "$count"
    done

    ok "Restored database ownership, schema ACL, marker and essential tables validated"
}

usage() {
    echo "Usage: $0 {--check|--restore} /path/to/wapt-dr-*.tar"
    exit 2
}

[ "$#" -eq 2 ] || usage

MODE="$1"
ARCHIVE="$2"

case "$MODE" in
    --check|--restore) ;;
    *) usage ;;
esac

if [ "$MODE" = "--restore" ] && [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || fail "Root privileges are required for --restore and sudo is not available"
    exec sudo -- "$0" "$@"
fi

echo "WAPT Server DR restore v${SCRIPT_VERSION}"
echo "=================================================="
if [ "$MODE" = "--check" ]; then
    echo "Mode: CHECK ONLY — no target WAPT data will be modified"
else
    echo "Mode: RESTORE — validation phase only"
fi
echo

for tool in tar sha256sum awk grep sed find wc mktemp pg_restore df stat sort; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool missing: $tool"
    ok "Tool available: $tool"
done

[ -f "$ARCHIVE" ] || fail "Archive not found: $ARCHIVE"
ok "Archive found: $ARCHIVE"
[ -s "$ARCHIVE" ] || fail "Archive is empty"
ok "Archive is not empty"

SIDECAR="${ARCHIVE}.sha256"
if [ -f "$SIDECAR" ]; then
    EXPECTED_ARCHIVE_SHA="$(awk 'NF {print $1; exit}' "$SIDECAR")"
    case "$EXPECTED_ARCHIVE_SHA" in
        ''|*[!0-9a-fA-F]*) fail "Invalid archive SHA256 sidecar: $SIDECAR" ;;
    esac
    [ "${#EXPECTED_ARCHIVE_SHA}" -eq 64 ] || fail "Invalid SHA256 length in sidecar"
    ACTUAL_ARCHIVE_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
    [ "${ACTUAL_ARCHIVE_SHA,,}" = "${EXPECTED_ARCHIVE_SHA,,}" ] || fail "Archive SHA256 sidecar mismatch"
    ok "Archive SHA256 sidecar validated"
else
    warn "Archive SHA256 sidecar not found: $SIDECAR"
fi

tar -tf "$ARCHIVE" >/dev/null || fail "Tar archive is not readable"
ok "Tar archive is readable"

if tar -tf "$ARCHIVE" | awk '
    /^\// { bad=1 }
    {
        n=split($0,a,"/")
        for (i=1;i<=n;i++) if (a[i]=="..") bad=1
    }
    END { exit bad ? 0 : 1 }
'; then
    fail "Archive contains unsafe paths"
fi
ok "Archive paths are safe"

BUNDLE_ROOT="$(tar -tf "$ARCHIVE" | sed 's#^\./##' | awk -F/ 'NF && $1!="" {print $1}' | sort -u)"
ROOT_COUNT="$(printf '%s\n' "$BUNDLE_ROOT" | awk 'NF {n++} END {print n+0}')"
[ "$ROOT_COUNT" -eq 1 ] || fail "Archive must contain exactly one top-level bundle root"
ok "Single bundle root found: $BUNDLE_ROOT"

# Validate the backup contract BEFORE extracting the potentially large repository.
MANIFEST_MEMBER="${BUNDLE_ROOT}/manifest.ini"
MANIFEST_PRECHECK="$(mktemp)" || fail "Unable to create temporary manifest file"
cleanup_manifest() { rm -f -- "${MANIFEST_PRECHECK:-}"; }
trap cleanup_manifest EXIT INT TERM HUP

tar -xOf "$ARCHIVE" "$MANIFEST_MEMBER" > "$MANIFEST_PRECHECK" 2>/dev/null || \
    fail "Unable to read manifest.ini directly from archive"
[ -s "$MANIFEST_PRECHECK" ] || fail "manifest.ini is empty"

ini_get_file() {
    file="$1"
    section="$2"
    key="$3"
    awk -v wanted_header="[$section]" -v wanted_key="$key" '
        $0 == wanted_header { active=1; next }
        /^\[/ { active=0 }
        active && $1 == wanted_key && $2 == "=" {
            print $3
            exit
        }
    ' "$file"
}

PRE_FORMAT_VERSION="$(ini_get_file "$MANIFEST_PRECHECK" backup format_version)"
[ "$PRE_FORMAT_VERSION" = "1" ] || \
    fail "Unsupported backup format_version: ${PRE_FORMAT_VERSION:-missing}"

PRE_REPO_INCLUDED="$(ini_get_file "$MANIFEST_PRECHECK" repository included)"
case "$PRE_REPO_INCLUDED" in yes|no) ;; *) fail "Invalid repository included value in manifest: ${PRE_REPO_INCLUDED:-missing}" ;; esac

PRE_REPO_MANIFEST="$(ini_get_file "$MANIFEST_PRECHECK" repository manifest_file)"
[ "$PRE_REPO_MANIFEST" = "metadata/repository-manifest.sha256" ] || \
    fail "Unsupported repository manifest path: ${PRE_REPO_MANIFEST:-missing}"

ok "Manifest contract precheck passed before full extraction"
rm -f -- "$MANIFEST_PRECHECK"
MANIFEST_PRECHECK=""
trap - EXIT INT TERM HUP

# IMPORTANT: large DR extraction MUST live on /var/www, never /tmp.
WORK_PARENT="/var/www"
[ -d "$WORK_PARENT" ] || fail "Restore work parent does not exist: $WORK_PARENT"
[ -w "$WORK_PARENT" ] || fail "Restore work parent is not writable: $WORK_PARENT"

ARCHIVE_BYTES="$(stat -c '%s' "$ARCHIVE")"
FREE_BYTES="$(df -PB1 "$WORK_PARENT" | awk 'NR==2 {print $4}')"
SAFETY_BYTES=$((2 * 1024 * 1024 * 1024))
REQUIRED_BYTES=$((ARCHIVE_BYTES + SAFETY_BYTES))

echo
echo "Restore check work filesystem: $WORK_PARENT"
echo "Archive size: $ARCHIVE_BYTES bytes"
echo "Free space:   $FREE_BYTES bytes"
echo "Required:     $REQUIRED_BYTES bytes (archive size + 2 GiB safety margin)"

[ "$FREE_BYTES" -ge "$REQUIRED_BYTES" ] || \
    fail "Insufficient free space on $WORK_PARENT for safe archive extraction"
ok "Free-space preflight passed"

WORKDIR="$(mktemp -d "${WORK_PARENT}/.wapt-dr-restore-check.XXXXXX")" || \
    fail "Unable to create restore check work directory under $WORK_PARENT"

cleanup() {
    if [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ]; then
        rm -rf -- "$WORKDIR"
    fi
}
trap cleanup EXIT INT TERM HUP

echo "Extracting bundle for validation under $WORK_PARENT..."
tar -xf "$ARCHIVE" -C "$WORKDIR" || fail "Archive extraction failed"

BUNDLE="$WORKDIR/$BUNDLE_ROOT"
[ -d "$BUNDLE" ] || fail "Extracted bundle root not found"
ok "Bundle extracted under $WORK_PARENT"

for f in \
    manifest.ini \
    SHA256SUMS \
    database/wapt.dump \
    config/waptserver.ini \
    config/nginx/wapt.conf \
    metadata/system.txt \
    metadata/packages.txt \
    metadata/database.txt \
    metadata/repository.txt \
    metadata/repository-manifest.sha256
do
    [ -f "$BUNDLE/$f" ] || fail "Required bundle file missing: $f"
done
ok "Required bundle files are present"

ini_get() {
    section="$1"
    key="$2"
    ini_get_file "$BUNDLE/manifest.ini" "$section" "$key"
}

FORMAT_VERSION="$(ini_get backup format_version)"
[ "$FORMAT_VERSION" = "1" ] || fail "Unsupported bundle format_version: ${FORMAT_VERSION:-missing}"
ok "Bundle format_version=1"

SOURCE_HOST="$(ini_get source hostname)"
SOURCE_FQDN="$(ini_get source fqdn)"
SOURCE_DEBIAN="$(ini_get source debian_major)"
SOURCE_WAPT="$(ini_get source waptserver_version)"
SOURCE_DB_MARKER="$(ini_get source db_version)"
SOURCE_PG_VERSION="$(ini_get database postgresql_version)"
SOURCE_PG_PORT="$(ini_get database postgresql_port)"
PACKAGE_PREFIX="$(ini_get site package_prefix)"
REPO_INCLUDED="$(ini_get repository included)"
REPO_FILES="$(ini_get repository files)"
REPO_MANIFEST_SHA="$(ini_get repository manifest_sha256)"

echo
echo "Source hostname:        ${SOURCE_HOST:-unknown}"
echo "Source FQDN:            ${SOURCE_FQDN:-unknown}"
echo "Source Debian:          ${SOURCE_DEBIAN:-unknown}"
echo "Source WAPT server:     ${SOURCE_WAPT:-unknown}"
echo "Source DB marker:       ${SOURCE_DB_MARKER:-unknown}"
echo "Source PostgreSQL:      ${SOURCE_PG_VERSION:-unknown}"
echo "Source PostgreSQL port: ${SOURCE_PG_PORT:-unknown} (metadata only)"
echo "Package prefix:         ${PACKAGE_PREFIX:-unknown}"
echo "Repository included:    ${REPO_INCLUDED:-unknown}"

CA_KEY="$(ini_get identity clients_signing_key)"
CA_CERT="$(ini_get identity clients_signing_certificate)"
TLS_CERT="$(ini_get identity tls_certificate)"
TLS_KEY="$(ini_get identity tls_key)"

for p in "$CA_KEY" "$CA_CERT" "$TLS_CERT" "$TLS_KEY"; do
    [ -n "$p" ] || fail "Mandatory identity path missing from manifest.ini"
done

for rel in \
    "certificates/client-ca/$(basename "$CA_KEY")" \
    "certificates/client-ca/$(basename "$CA_CERT")" \
    "certificates/server-tls/$(basename "$TLS_CERT")" \
    "certificates/server-tls/$(basename "$TLS_KEY")"
do
    [ -f "$BUNDLE/$rel" ] || fail "Mandatory identity file missing: $rel"
done
ok "Mandatory identity files are present"

REPO_MANIFEST="$BUNDLE/metadata/repository-manifest.sha256"
ACTUAL_REPO_MANIFEST_SHA="$(sha256sum "$REPO_MANIFEST" | awk '{print $1}')"
[ "$ACTUAL_REPO_MANIFEST_SHA" = "$REPO_MANIFEST_SHA" ] || \
    fail "Repository manifest SHA256 mismatch"
ok "Repository manifest SHA256 validated"

case "$REPO_INCLUDED" in
    yes)
        [ -d "$BUNDLE/repository/wapt" ] || \
            fail "Repository declared included but repository directory is missing"

        ACTUAL_REPO_FILES="$(find "$BUNDLE/repository/wapt" -type f | wc -l)"
        [ "$ACTUAL_REPO_FILES" = "$REPO_FILES" ] || \
            fail "Repository file count mismatch: expected $REPO_FILES, got $ACTUAL_REPO_FILES"

        echo "Validating repository file SHA256 manifest..."
        (
            cd "$BUNDLE/repository/wapt" || exit 1
            sha256sum -c "$REPO_MANIFEST"
        ) >/dev/null || fail "Repository file SHA256 validation failed"
        ok "Repository validated: $ACTUAL_REPO_FILES files"
        ;;
    no)
        [ ! -d "$BUNDLE/repository/wapt" ] || \
            fail "Repository declared excluded but repository directory exists"
        ok "Repository correctly excluded"
        ;;
    *)
        fail "Invalid repository included value: ${REPO_INCLUDED:-missing}"
        ;;
esac

echo "Validating bundle SHA256SUMS..."
(
    cd "$BUNDLE" || exit 1
    sha256sum -c SHA256SUMS
) >/dev/null || fail "Bundle SHA256SUMS validation failed"
ok "Bundle SHA256SUMS validated"

pg_restore -l "$BUNDLE/database/wapt.dump" >/dev/null 2>&1 || \
    fail "Database dump is not a valid pg_restore custom-format archive"
ok "Database dump is readable by pg_restore"

if [ "$MODE" = "--restore" ]; then
    echo
    echo "Validating restore target..."

    for tool in dpkg-query pg_lsclusters psql pg_dump pg_restore dropdb createdb runuser systemctl; do
        command -v "$tool" >/dev/null 2>&1 || fail "Required restore tool missing: $tool"
        ok "Restore tool available: $tool"
    done

    [ -r /etc/os-release ] || fail "Unable to read /etc/os-release"
    . /etc/os-release
    TARGET_DEBIAN="${VERSION_ID:-}"
    [ -n "$TARGET_DEBIAN" ] || fail "Unable to determine target Debian version"

    TARGET_WAPT="$(dpkg-query -W -f='${Version}' tis-waptserver 2>/dev/null)" || \
        fail "Target package tis-waptserver is not installed"
    TARGET_SETUP="$(dpkg-query -W -f='${Version}' tis-waptsetup 2>/dev/null)" || \
        fail "Target package tis-waptsetup is not installed"

    systemctl is-active --quiet postgresql || fail "Target PostgreSQL service is not active"

    TARGET_WAPTSERVER_ACTIVE="yes"
    if ! systemctl is-active --quiet waptserver; then
        TARGET_WAPTSERVER_ACTIVE="no"
        warn "Target waptserver service is not active; interrupted-restore state will be checked after PostgreSQL target detection"
    fi

    TARGET_CLUSTERS="$(pg_lsclusters --no-header 2>/dev/null | awk '$4=="online" {print $1 "|" $2 "|" $3 "|" $4 "|" $5}')"
    TARGET_CLUSTER_COUNT="$(printf '%s\n' "$TARGET_CLUSTERS" | awk 'NF {n++} END {print n+0}')"
    [ "$TARGET_CLUSTER_COUNT" -ge 1 ] || fail "No online PostgreSQL cluster found on target"

    TARGET_WAPT_CLUSTERS=""
    while IFS='|' read -r pg_major pg_cluster pg_port pg_status pg_owner; do
        [ -n "$pg_major" ] || continue
        if (cd / && runuser -u postgres -- \
            psql -p "$pg_port" -d wapt -Atqc "SELECT 1;" >/dev/null 2>&1); then
            TARGET_WAPT_CLUSTERS="${TARGET_WAPT_CLUSTERS}${pg_major}|${pg_cluster}|${pg_port}|${pg_status}|${pg_owner}
"
        fi
    done <<EOF
$TARGET_CLUSTERS
EOF

    TARGET_WAPT_CLUSTER_COUNT="$(printf '%s\n' "$TARGET_WAPT_CLUSTERS" | awk 'NF {n++} END {print n+0}')"
    [ "$TARGET_WAPT_CLUSTER_COUNT" -eq 1 ] || \
        fail "Expected exactly one online PostgreSQL cluster containing database wapt, found $TARGET_WAPT_CLUSTER_COUNT"

    TARGET_PG_MAJOR="$(printf '%s\n' "$TARGET_WAPT_CLUSTERS" | awk -F'|' 'NF {print $1; exit}')"
    TARGET_PG_CLUSTER="$(printf '%s\n' "$TARGET_WAPT_CLUSTERS" | awk -F'|' 'NF {print $2; exit}')"
    TARGET_PG_PORT="$(printf '%s\n' "$TARGET_WAPT_CLUSTERS" | awk -F'|' 'NF {print $3; exit}')"
    TARGET_PG_OWNER="$(printf '%s\n' "$TARGET_WAPT_CLUSTERS" | awk -F'|' 'NF {print $5; exit}')"

    if [ "$TARGET_WAPTSERVER_ACTIVE" = "no" ]; then
        TARGET_PUBLIC_TABLE_COUNT="$(cd / && runuser -u postgres -- \
            psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
            "SELECT count(*) FROM pg_tables WHERE schemaname='public';" \
            2>/dev/null)" || fail "Unable to assess interrupted-restore database state"
        [ "$TARGET_PUBLIC_TABLE_COUNT" = "0" ] || \
            fail "Target waptserver is inactive and database is not an empty interrupted-restore state (${TARGET_PUBLIC_TABLE_COUNT} public tables)"
        warn "Interrupted restore state detected: waptserver inactive and target database has 0 public tables"
        ok "Interrupted restore state accepted for controlled database restore resume"
    fi

    [ "$TARGET_PG_OWNER" = "postgres" ] || \
        fail "Target PostgreSQL cluster owner is not postgres: $TARGET_PG_OWNER"

    TARGET_DB_RUNTIME="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT current_database(), current_setting('server_version'), current_setting('port');" \
        2>/dev/null)" || fail "Unable to connect to target WAPT database"

    TARGET_DB_NAME="$(printf '%s\n' "$TARGET_DB_RUNTIME" | awk -F'|' 'NR==1 {print $1}')"
    TARGET_PG_VERSION="$(printf '%s\n' "$TARGET_DB_RUNTIME" | awk -F'|' 'NR==1 {print $2}')"
    TARGET_DB_PORT="$(printf '%s\n' "$TARGET_DB_RUNTIME" | awk -F'|' 'NR==1 {print $3}')"

    [ "$TARGET_DB_NAME" = "wapt" ] || fail "Unexpected target database name: $TARGET_DB_NAME"
    [ "$TARGET_DB_PORT" = "$TARGET_PG_PORT" ] || \
        fail "Target PostgreSQL port mismatch between cluster and database runtime"

    TARGET_DB_OWNER="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d postgres -Atqc \
        "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='wapt';" \
        2>/dev/null)" || fail "Unable to determine target WAPT database owner"
    [ "$TARGET_DB_OWNER" = "wapt" ] || \
        fail "Target WAPT database owner is not wapt: ${TARGET_DB_OWNER:-missing}"

    if [ "$TARGET_WAPTSERVER_ACTIVE" = "yes" ]; then
        TARGET_DB_MARKER="$(cd / && runuser -u postgres -- \
            psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
            "SELECT value FROM serverattribs WHERE key='db_version';" \
            2>/dev/null)" || fail "Unable to read target WAPT database marker"
        [ -n "$TARGET_DB_MARKER" ] || fail "Target WAPT database marker is empty"
    else
        TARGET_DB_MARKER="<interrupted-empty>"
        warn "Target DB marker check skipped for accepted empty interrupted-restore state"
    fi

    echo
    echo "Target Debian:          $TARGET_DEBIAN"
    echo "Target WAPT server:     $TARGET_WAPT"
    echo "Target WAPT setup:      $TARGET_SETUP"
    echo "Target PostgreSQL:      $TARGET_PG_VERSION"
    echo "Target PG cluster:      $TARGET_PG_MAJOR/$TARGET_PG_CLUSTER"
    echo "Target PostgreSQL port: $TARGET_PG_PORT"
    echo "Target DB owner:        $TARGET_DB_OWNER"
    echo "Target DB marker:       $TARGET_DB_MARKER"
    echo
    ok "Restore target precheck passed"
fi

echo
if [ "$MODE" = "--check" ]; then
    echo "CHECK PASSED"
    echo "No target WAPT data was modified."
else
    echo "RESTORE PRECHECK PASSED"
    echo
    [ "$(id -u)" -eq 0 ] || fail "Root privileges are required to create the target safety backup"
    [ -d /var/www/wapt-backups ] || mkdir -p /var/www/wapt-backups
    chmod 0700 /var/www/wapt-backups || fail "Unable to secure /var/www/wapt-backups"

    create_target_safety_backup

    echo
    echo "SAFETY BACKUP PASSED"

    restore_target_database

    echo
    echo "DATABASE RESTORE PASSED"
    echo "The target WAPT database has been replaced and validated."
    echo "waptserver/wapttasks remain stopped intentionally."
    echo "Target configuration, certificates, nginx configuration and repository were NOT replaced."
    echo "Safety backup retained at: $SAFETY_ARCHIVE"
    echo
    echo "STOP BARRIER: configuration/identity/repository restore is not implemented yet in v${SCRIPT_VERSION}."
    exit 3
fi
