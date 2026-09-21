#!/bin/bash
set -u

SCRIPT_VERSION="1.0"
BACKUP_FORMAT_VERSION="1"
EXPECTED_DEBIAN_MAJOR="10"

WAPT_CONFIG="/opt/wapt/conf/waptserver.ini"
NGINX_CONFIG="/etc/nginx/sites-available/wapt.conf"
WAPT_REPOSITORY="/var/www/wapt"
BACKUP_ROOT="/var/www/wapt-backups"

ok()    { echo "[ OK ] $*"; }
warn()  { echo "[WARN] $*"; }
block() { echo "[BLOCK] $*"; BLOCKING=$((BLOCKING + 1)); }
die()   { echo "[BLOCK] $*" >&2; exit 1; }

BLOCKING=0
WAPT_DB_COUNT=0
WAPT_DB_PORT=""
WAPT_DB_VERSION=""
DB_VERSION=""
WAPT_VERSION=""
WAPTSETUP_VERSION=""
CLIENTS_SIGNING_KEY=""
CLIENTS_SIGNING_CERTIFICATE=""
TLS_CERTIFICATE=""
TLS_KEY=""
REPO_FILES=""
REPO_SIZE_BYTES=""

read_ini_value() {
    local key="$1"
    local file="$2"
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$/\1/p" "$file" | head -n 1
}

read_nginx_path() {
    local directive="$1"
    local file="$2"
    sed -n -E "s|^[[:space:]]*${directive}[[:space:]]+[\"']?([^;\"']+)[\"']?;[[:space:]]*$|\1|p" "$file" | head -n 1
}

discover_identity_files() {
    CLIENTS_SIGNING_KEY="$(read_ini_value clients_signing_key "$WAPT_CONFIG")"
    CLIENTS_SIGNING_CERTIFICATE="$(read_ini_value clients_signing_certificate "$WAPT_CONFIG")"
    TLS_CERTIFICATE="$(read_nginx_path ssl_certificate "$NGINX_CONFIG")"
    TLS_KEY="$(read_nginx_path ssl_certificate_key "$NGINX_CONFIG")"
}

detect_database() {
    WAPT_DB_COUNT=0
    WAPT_DB_PORT=""
    WAPT_DB_VERSION=""
    command -v pg_lsclusters >/dev/null 2>&1 || return 1
    while read -r pg_version pg_cluster pg_port pg_status pg_owner rest; do
        [ "$pg_status" = "online" ] || continue
        if runuser -u postgres -- sh -c 'cd / && exec "$@"' sh psql -p "$pg_port" -Atc \
            "SELECT 1 FROM pg_database WHERE datname='wapt';" 2>/dev/null | grep -qx '1'; then
            WAPT_DB_COUNT=$((WAPT_DB_COUNT + 1))
            WAPT_DB_PORT="$pg_port"
            WAPT_DB_VERSION="$pg_version"
        fi
    done < <(pg_lsclusters --no-header)
    [ "$WAPT_DB_COUNT" -eq 1 ]
}

detect_package_prefix() {
    local prefixes count
    prefixes="$(find "$WAPT_REPOSITORY" -maxdepth 1 -type f -name '*-waptupgrade_*.wapt' -printf '%f\n' 2>/dev/null \
        | sed -n 's/^\(.*\)-waptupgrade_.*/\1/p' | sort -u)"
    if [ -z "$prefixes" ]; then
        PACKAGE_PREFIX=""
        PACKAGE_PREFIX_STATUS="not-found"
        return 0
    fi
    count="$(printf '%s\n' "$prefixes" | wc -l | awk '{print $1}')"
    if [ "$count" -eq 1 ]; then
        PACKAGE_PREFIX="$prefixes"
        PACKAGE_PREFIX_STATUS="detected"
        return 0
    fi
    PACKAGE_PREFIX=""
    PACKAGE_PREFIX_STATUS="ambiguous"
    PACKAGE_PREFIX_CANDIDATES="$(printf '%s\n' "$prefixes" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    return 1
}

generate_repository_manifest() {
    local output="$1"
    ( cd "$WAPT_REPOSITORY" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) > "$output"
}

normalize_bundle_security() {
    local d="$1"
    chown -R root:root "$d"
    find "$d" -type d -exec chmod 0700 {} +
    find "$d" -type f -exec chmod 0600 {} +
}

copy_repository_into_bundle() {
    local bundle_dir="$1"
    mkdir -p "$bundle_dir/repository/wapt"
    cp -a "$WAPT_REPOSITORY"/. "$bundle_dir/repository/wapt"/ || die "Repository copy failed"

    local copied_files
    copied_files="$(find "$bundle_dir/repository/wapt" -type f | wc -l | awk '{print $1}')"
    [ "$copied_files" -eq "$REPO_FILES" ] || die "Copied repository file count mismatch: expected $REPO_FILES, got $copied_files"

    (
        cd "$bundle_dir/repository/wapt" || exit 1
        sha256sum -c "$bundle_dir/metadata/repository-manifest.sha256" >/dev/null
    ) || die "Copied repository SHA256 validation failed"
    ok "Repository copied and SHA256-validated: $copied_files files"
}

create_final_archive() {
    local final_dir="$1"
    local archive_path="${final_dir}.tar"
    local parent base

    parent="$(dirname "$final_dir")"
    base="$(basename "$final_dir")"

    tar -C "$parent" -cf "$archive_path" "$base" || die "Final tar creation failed"
    [ -s "$archive_path" ] || die "Final tar archive is empty"
    tar -tf "$archive_path" >/dev/null || die "Final tar archive validation failed"

    sha256sum "$archive_path" > "${archive_path}.sha256" || die "Final archive SHA256 creation failed"
    chmod 0600 "$archive_path" "${archive_path}.sha256"

    FINAL_ARCHIVE="$archive_path"
    FINAL_ARCHIVE_SHA256="$(awk '{print $1}' "${archive_path}.sha256")"
    ok "Final tar archive created and validated"
}

precheck() {
    BLOCKING=0
    echo "WAPT Server DR backup precheck v${SCRIPT_VERSION}"
    echo "=================================================="
    echo

    [ "$(id -u)" -eq 0 ] && ok "Running as root" || block "Must be run as root"

    if [ -r /etc/os-release ]; then
        . /etc/os-release
        echo "OS: ${PRETTY_NAME:-unknown}"
        [ "${VERSION_ID:-}" = "$EXPECTED_DEBIAN_MAJOR" ] \
            && ok "Debian ${EXPECTED_DEBIAN_MAJOR}" \
            || block "Expected Debian ${EXPECTED_DEBIAN_MAJOR}, found ${VERSION_ID:-unknown}"
    else
        block "/etc/os-release unavailable"
    fi

    WAPT_VERSION="$(dpkg-query -W -f='${Version}' tis-waptserver 2>/dev/null || true)"
    WAPTSETUP_VERSION="$(dpkg-query -W -f='${Version}' tis-waptsetup 2>/dev/null || true)"
    echo "tis-waptserver: ${WAPT_VERSION:-not installed}"
    echo "tis-waptsetup : ${WAPTSETUP_VERSION:-not installed}"
    [ -n "$WAPT_VERSION" ] && ok "WAPT server package found" || block "tis-waptserver is not installed"

    [ -f "$WAPT_CONFIG" ] \
        && { ok "Configuration found: $WAPT_CONFIG"; echo "Config SHA256: $(sha256sum "$WAPT_CONFIG" | awk '{print $1}')"; } \
        || block "Configuration missing: $WAPT_CONFIG"
    [ -f "$NGINX_CONFIG" ] && ok "nginx WAPT configuration found: $NGINX_CONFIG" \
        || block "nginx WAPT configuration missing: $NGINX_CONFIG"

    for cmd in pg_dump pg_restore psql sha256sum tar openssl dpkg-query runuser stat df hostname find du sed grep awk mktemp cp date sort xargs tr wc; do
        command -v "$cmd" >/dev/null 2>&1 && ok "Tool available: $cmd" || block "Required tool missing: $cmd"
    done

    for service in waptserver wapttasks nginx; do
        systemctl is-active --quiet "$service" && ok "Service $service active" || warn "Service $service is not active"
    done

    if detect_database; then
        ok "WAPT database found on PostgreSQL ${WAPT_DB_VERSION}, port ${WAPT_DB_PORT}"
    else
        [ "$WAPT_DB_COUNT" -eq 0 ] && block "No WAPT database found" || block "WAPT database found on multiple PostgreSQL clusters"
    fi

    if [ "$WAPT_DB_COUNT" -eq 1 ]; then
        DB_VERSION="$(runuser -u postgres -- sh -c 'cd / && exec "$@"' sh psql -p "$WAPT_DB_PORT" -d wapt -Atc \
            "SELECT value::text FROM serverattribs WHERE key='db_version';" 2>/dev/null || true)"
        echo "Database marker: ${DB_VERSION:-unknown}"
        [ -n "$DB_VERSION" ] || block "Unable to read WAPT database marker"
        echo
        echo "Database baseline:"
        for table in hostgroups hostpackagesstatus hosts hostsoftwares packages waptusers; do
            count="$(runuser -u postgres -- sh -c 'cd / && exec "$@"' sh psql -p "$WAPT_DB_PORT" -d wapt -Atc "SELECT count(*) FROM ${table};" 2>/dev/null || true)"
            printf "  %-20s %s\n" "$table" "${count:-ERROR}"
            [ -n "$count" ] || block "Unable to count table ${table}"
        done
    fi

    echo
    echo "Repository:"
    if [ -d "$WAPT_REPOSITORY" ]; then
        REPO_FILES="$(find "$WAPT_REPOSITORY" -type f | wc -l)"
        REPO_SIZE_BYTES="$(du -sb "$WAPT_REPOSITORY" 2>/dev/null | awk '{print $1}')"
        echo "  Path       : $WAPT_REPOSITORY"
        echo "  Files      : $REPO_FILES"
        echo "  Size bytes : ${REPO_SIZE_BYTES:-unknown}"
        ok "Repository found"

    if detect_package_prefix; then
        if [ "$PACKAGE_PREFIX_STATUS" = "detected" ]; then
            echo "Historical package prefix: $PACKAGE_PREFIX"
            ok "Historical package prefix detected"
        else
            warn "Historical package prefix not found in repository"
        fi
    else
        block "Historical package prefix is ambiguous: ${PACKAGE_PREFIX_CANDIDATES:-unknown}"
    fi
    else
        block "Repository $WAPT_REPOSITORY missing"
    fi

    discover_identity_files
    echo
    echo "Identity files:"
    [ -n "$CLIENTS_SIGNING_CERTIFICATE" ] && [ -f "$CLIENTS_SIGNING_CERTIFICATE" ] \
        && ok "Client signing certificate: $CLIENTS_SIGNING_CERTIFICATE" || block "Client signing certificate missing or unresolved"
    [ -n "$CLIENTS_SIGNING_KEY" ] && [ -f "$CLIENTS_SIGNING_KEY" ] \
        && ok "Client signing private key: $CLIENTS_SIGNING_KEY" || block "Client signing private key missing or unresolved"
    [ -n "$TLS_CERTIFICATE" ] && [ -f "$TLS_CERTIFICATE" ] \
        && ok "TLS certificate: $TLS_CERTIFICATE" || block "TLS certificate missing or unresolved"
    [ -n "$TLS_KEY" ] && [ -f "$TLS_KEY" ] \
        && ok "TLS private key: $TLS_KEY" || block "TLS private key missing or unresolved"

    [ -f "${CLIENTS_SIGNING_CERTIFICATE:-/nonexistent}" ] && \
        { openssl x509 -in "$CLIENTS_SIGNING_CERTIFICATE" -noout >/dev/null 2>&1 \
          && ok "Client signing certificate parses correctly" || block "Client signing certificate cannot be parsed"; }
    [ -f "${TLS_CERTIFICATE:-/nonexistent}" ] && \
        { openssl x509 -in "$TLS_CERTIFICATE" -noout >/dev/null 2>&1 \
          && ok "TLS certificate parses correctly" || block "TLS certificate cannot be parsed"; }

    echo
    [ "$BLOCKING" -eq 0 ] && { ok "PRECHECK PASSED"; return 0; }
    echo "[BLOCK] PRECHECK FAILED: ${BLOCKING} blocking issue(s)"
    return 1
}

database_count() {
    runuser -u postgres -- sh -c 'cd / && exec "$@"' sh psql -p "$WAPT_DB_PORT" -d wapt -Atc "SELECT count(*) FROM ${1};"
}

backup_bundle() {
    local include_repository="${1:-yes}"
    precheck || die "Backup aborted because precheck failed"

    local timestamp hostname_short bundle_name work_parent bundle_dir final_dir server_uuid
    timestamp="$(date -u +%Y%m%d-%H%M%S)"
    hostname_short="$(hostname -s)"
    bundle_name="wapt-dr-${hostname_short}-${timestamp}"
    if [ "$include_repository" = "yes" ]; then
        # One repository staging copy + final tar + 2 GiB safety margin.
        local available_bytes required_bytes safety_bytes
        available_bytes="$(df -PB1 "$BACKUP_ROOT" | awk 'NR==2 {print $4}')"
        safety_bytes=$((2 * 1024 * 1024 * 1024))
        required_bytes=$((2 * REPO_SIZE_BYTES + safety_bytes))
        echo "Backup filesystem free bytes : $available_bytes"
        echo "Required free bytes           : $required_bytes"
        [ "$available_bytes" -ge "$required_bytes" ] || die "Insufficient free space on backup filesystem before repository backup"
        ok "Sufficient free space on backup filesystem"
    fi

    work_parent="$(mktemp -d "${BACKUP_ROOT}/.wapt-dr-work.XXXXXXXX")" || die "Unable to create temporary work directory in $BACKUP_ROOT"
    bundle_dir="${work_parent}/${bundle_name}"

    trap 'rc=$?; if [ "$rc" -ne 0 ]; then echo "[BLOCK] Backup failed; temporary data preserved at: '"$work_parent"'" >&2; fi' EXIT
    umask 077

    mkdir -p "$bundle_dir/database" "$bundle_dir/config/nginx" \
        "$bundle_dir/certificates/client-ca" "$bundle_dir/certificates/server-tls" \
        "$bundle_dir/metadata" || die "Unable to create bundle structure"

    echo
    detect_package_prefix || die "Historical package prefix is ambiguous: ${PACKAGE_PREFIX_CANDIDATES:-unknown}"

    echo "Creating DR backup"
    echo "====================================="
    echo "Working directory: $bundle_dir"

    if ! runuser -u postgres -- sh -c 'cd / && exec "$@"' sh pg_dump -p "$WAPT_DB_PORT" -Fc -d wapt \
        > "$bundle_dir/database/wapt.dump"; then
        rm -f "$bundle_dir/database/wapt.dump"
        die "PostgreSQL dump failed"
    fi
    [ -s "$bundle_dir/database/wapt.dump" ] || die "PostgreSQL dump is empty"
    pg_restore -l "$bundle_dir/database/wapt.dump" >/dev/null 2>&1 || die "PostgreSQL dump validation failed"
    ok "PostgreSQL dump created and validated"

    cp -a "$WAPT_CONFIG" "$bundle_dir/config/waptserver.ini" || die "Unable to copy waptserver.ini"
    cp -a "$NGINX_CONFIG" "$bundle_dir/config/nginx/wapt.conf" || die "Unable to copy nginx WAPT configuration"
    cp -a "$CLIENTS_SIGNING_CERTIFICATE" "$bundle_dir/certificates/client-ca/" || die "Unable to copy client signing certificate"
    cp -a "$CLIENTS_SIGNING_KEY" "$bundle_dir/certificates/client-ca/" || die "Unable to copy client signing private key"
    cp -a "$TLS_CERTIFICATE" "$bundle_dir/certificates/server-tls/" || die "Unable to copy TLS certificate"
    cp -a "$TLS_KEY" "$bundle_dir/certificates/server-tls/" || die "Unable to copy TLS private key"
    ok "Configuration and identity files copied"

    echo "Generating repository SHA256 manifest (repository content is NOT copied)..."
    generate_repository_manifest "$bundle_dir/metadata/repository-manifest.sha256" || die "Repository SHA256 manifest generation failed"
    [ -s "$bundle_dir/metadata/repository-manifest.sha256" ] || die "Repository SHA256 manifest is empty"
    REPO_MANIFEST_LINES="$(wc -l < "$bundle_dir/metadata/repository-manifest.sha256" | awk '{print $1}')"
    [ "$REPO_MANIFEST_LINES" -eq "$REPO_FILES" ] || die "Repository manifest count mismatch: expected $REPO_FILES, got $REPO_MANIFEST_LINES"
    REPO_MANIFEST_SHA256="$(sha256sum "$bundle_dir/metadata/repository-manifest.sha256" | awk '{print $1}')"
    ok "Repository SHA256 manifest created: $REPO_MANIFEST_LINES files"

    if [ "$include_repository" = "yes" ]; then
        echo "Copying repository into DR bundle..."
        copy_repository_into_bundle "$bundle_dir"
        REPOSITORY_INCLUDED="yes"
    else
        REPOSITORY_INCLUDED="no"
    fi

    {
        echo "backup_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "hostname=$(hostname)"
        echo "fqdn=$(hostname -f 2>/dev/null || hostname)"
        echo "kernel=$(uname -srmo)"
        . /etc/os-release
        echo "distribution=${PRETTY_NAME:-unknown}"
        echo "distribution_version=${VERSION_ID:-unknown}"
    } > "$bundle_dir/metadata/system.txt"

    {
        echo "tis-waptserver=${WAPT_VERSION:-not-installed}"
        echo "tis-waptsetup=${WAPTSETUP_VERSION:-not-installed}"
        echo "postgresql=$(psql --version 2>/dev/null || true)"
        echo "nginx=$(nginx -v 2>&1 || true)"
    } > "$bundle_dir/metadata/packages.txt"

    {
        echo "database=wapt"
        echo "postgresql_cluster_version=$WAPT_DB_VERSION"
        echo "postgresql_port=$WAPT_DB_PORT"
        echo "db_version=$DB_VERSION"
        for table in hostgroups hostpackagesstatus hosts hostsoftwares packages waptusers; do
            echo "${table}=$(database_count "$table")"
        done
    } > "$bundle_dir/metadata/database.txt" || die "Unable to write database metadata"

    {
        echo "repository_path=$WAPT_REPOSITORY"
        echo "repository_included=$REPOSITORY_INCLUDED"
        echo "repository_files=$REPO_FILES"
        echo "repository_size_bytes=$REPO_SIZE_BYTES"
        echo "repository_manifest_generated=yes"
        echo "repository_manifest_sha256=$REPO_MANIFEST_SHA256"
        if [ "$REPOSITORY_INCLUDED" = "yes" ]; then
            echo "note=Repository content is included and verified against the per-file SHA256 manifest."
        else
            echo "note=Repository content is not included; per-file SHA256 manifest is included for separate transfer validation."
        fi
    } > "$bundle_dir/metadata/repository.txt"

    server_uuid="$(read_ini_value server_uuid "$WAPT_CONFIG")"
    cat > "$bundle_dir/manifest.ini" <<EOF
[backup]
format_version = ${BACKUP_FORMAT_VERSION}
script_version = ${SCRIPT_VERSION}
created_utc = $(date -u '+%Y-%m-%dT%H:%M:%SZ')

[source]
hostname = $(hostname)
fqdn = $(hostname -f 2>/dev/null || hostname)
debian_major = ${EXPECTED_DEBIAN_MAJOR}
waptserver_version = ${WAPT_VERSION}
waptsetup_version = ${WAPTSETUP_VERSION}
db_version = ${DB_VERSION}
server_uuid = ${server_uuid}

[database]
name = wapt
postgresql_version = ${WAPT_DB_VERSION}
postgresql_port = ${WAPT_DB_PORT}

[repository]
path = ${WAPT_REPOSITORY}
included = ${REPOSITORY_INCLUDED}
files = ${REPO_FILES}
size_bytes = ${REPO_SIZE_BYTES}
manifest_generated = yes
manifest_file = metadata/repository-manifest.sha256
manifest_sha256 = ${REPO_MANIFEST_SHA256}

[site]
package_prefix = ${PACKAGE_PREFIX}
package_prefix_status = ${PACKAGE_PREFIX_STATUS}

[identity]
clients_signing_certificate = $(basename "$CLIENTS_SIGNING_CERTIFICATE")
clients_signing_key = $(basename "$CLIENTS_SIGNING_KEY")
tls_certificate = $(basename "$TLS_CERTIFICATE")
tls_key = $(basename "$TLS_KEY")

[restore_policy]
nginx_historical_config_reference_only = yes
preserve_target_waptsetup = yes
preserve_target_waptdeploy = yes
regenerate_waptagent_after_restore = yes
EOF

    normalize_bundle_security "$bundle_dir"
    ok "Bundle permissions normalized: root:root, directories 0700, files 0600"

    (
        cd "$bundle_dir" || exit 1
        find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
        chmod 0600 SHA256SUMS
        sha256sum -c SHA256SUMS >/dev/null
    ) || die "Bundle SHA256 validation failed"
    ok "Bundle SHA256SUMS created and validated"

    mkdir -p "$BACKUP_ROOT" || die "Unable to create $BACKUP_ROOT"
    final_dir="${BACKUP_ROOT}/${bundle_name}"
    [ ! -e "$final_dir" ] || die "Final backup path already exists: $final_dir"
    mv "$bundle_dir" "$final_dir"
    chmod 0700 "$final_dir"

    create_final_archive "$final_dir"

    # The .tar is the sole administrator-visible backup artifact.
    # Remove the extracted/staging bundle only after tar creation and validation.
    rm -rf -- "$final_dir"
    [ ! -e "$final_dir" ] || die "Unable to remove staging backup directory: $final_dir"

    rm -rf -- "$work_parent"
    trap - EXIT

    echo
    ok "BACKUP PASSED"
    echo "Final archive       : $FINAL_ARCHIVE"
    echo "Archive SHA256      : $FINAL_ARCHIVE_SHA256"
    echo "Repository included : $(printf '%s' "$REPOSITORY_INCLUDED" | tr '[:lower:]' '[:upper:]')"

    if [ "$REPOSITORY_INCLUDED" = "no" ]; then
        echo
        echo "IMPORTANT:"
        echo "  Repository content is not inside the archive."
        echo "  Its per-file SHA256 manifest is included for separate repository validation."
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            echo "Administrative privileges are required; requesting sudo..."
            exec sudo -- "$0" "$@"
        else
            echo "[BLOCK] This operation must be run as root and sudo is unavailable." >&2
            exit 1
        fi
    fi
}

require_root "$@"

case "${1:-precheck}" in
    precheck) precheck ;;
    backup) backup_bundle yes ;;
    backup-no-repository) backup_bundle no ;;
    *)
        echo "Usage: $0 {precheck|backup|backup-no-repository}"
        exit 2
        ;;
esac
