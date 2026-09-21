#!/bin/bash
set -u

SCRIPT_VERSION="0.7.2"

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


metadata_value() {
    file="$1"
    key="$2"
    sed -n -E "s/^${key}=(.*)$/\1/p" "$file" | head -n 1
}

validate_post_database_state() {
    DB_METADATA="$BUNDLE/metadata/database.txt"
    [ -f "$DB_METADATA" ] || return 1

    POST_DB_MARKER="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT value FROM serverattribs WHERE key='db_version';" 2>/dev/null)" || return 1
    [ -n "$POST_DB_MARKER" ] || return 1
    [ "$POST_DB_MARKER" = "$SOURCE_DB_MARKER" ] || return 1

    POST_DB_OWNER="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d postgres -Atqc \
        "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='wapt';" 2>/dev/null)" || return 1
    [ "$POST_DB_OWNER" = "wapt" ] || return 1

    POST_SCHEMA_ACL="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT has_schema_privilege('wapt','public','USAGE')::int || '|' || has_schema_privilege('wapt','public','CREATE')::int;" 2>/dev/null)" || return 1
    [ "$POST_SCHEMA_ACL" = "1|1" ] || return 1

    NON_WAPT_TABLES="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tableowner <> 'wapt';" 2>/dev/null)" || return 1
    [ "$NON_WAPT_TABLES" = "0" ] || return 1

    NON_WAPT_SEQUENCES="$(cd / && runuser -u postgres -- \
        psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
        "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='S' AND pg_get_userbyid(c.relowner) <> 'wapt';" 2>/dev/null)" || return 1
    [ "$NON_WAPT_SEQUENCES" = "0" ] || return 1

    for table in hostgroups hostpackagesstatus hosts hostsoftwares packages waptusers; do
        expected="$(metadata_value "$DB_METADATA" "$table")"
        case "$expected" in
            ''|*[!0-9]*) return 1 ;;
        esac
        actual="$(cd / && runuser -u postgres -- \
            psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
            "SELECT count(*) FROM public.${table};" 2>/dev/null)" || return 1
        [ "$actual" = "$expected" ] || return 1
    done

    return 0
}

wapt_ini_value() {
    file="$1"
    key="$2"
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\\1/p" "$file" | head -n 1
}

restore_target_configuration_identity() {
    echo
    echo "=================================================="
    echo "CONFIGURATION / IDENTITY PHASE"
    echo "=================================================="
    echo "Restoring historical WAPT identity and policy while preserving target runtime settings."

    TARGET_INI="/opt/wapt/conf/waptserver.ini"
    SOURCE_INI="$BUNDLE/config/waptserver.ini"
    [ -f "$TARGET_INI" ] || fail "Target waptserver.ini is missing: $TARGET_INI"
    [ -f "$SOURCE_INI" ] || fail "Source waptserver.ini is missing from bundle"

    MERGED_INI="$(mktemp /opt/wapt/conf/.waptserver.ini.restore.XXXXXX)" || \
        fail "Unable to create temporary merged waptserver.ini"
    cp -a "$TARGET_INI" "$MERGED_INI" || fail "Unable to seed merged waptserver.ini"

    RESTORE_KEYS="allow_unauthenticated_connect allow_unauthenticated_registration clients_signing_certificate clients_signing_key secret_key server_uuid wapt_password"
    for key in $RESTORE_KEYS; do
        source_value="$(wapt_ini_value "$SOURCE_INI" "$key")"
        [ -n "$source_value" ] || fail "Source waptserver.ini value missing: $key"
        awk -v wanted="$key" -v value="$source_value" '
            BEGIN { replaced=0 }
            {
                line=$0
                split(line,a,"=")
                lhs=a[1]
                gsub(/^[ \t]+|[ \t]+$/, "", lhs)
                if (lhs == wanted) {
                    print wanted " = " value
                    replaced=1
                } else {
                    print line
                }
            }
            END { if (!replaced) exit 42 }
        ' "$MERGED_INI" > "${MERGED_INI}.new" || {
            rm -f -- "${MERGED_INI}.new" "$MERGED_INI"
            fail "Unable to merge WAPT identity/policy key: $key"
        }
        mv "${MERGED_INI}.new" "$MERGED_INI" || fail "Unable to update merged waptserver.ini"
    done

    # Runtime/technical keys remain authoritative from the target installation.
    RUNTIME_KEYS="chdir gid http-socket processes uid wapt_folder wapt_huey_db wapt_user waptwua_folder wsgi master enable-threads max-requests"
    for key in $RUNTIME_KEYS; do
        before="$(wapt_ini_value "$TARGET_INI" "$key")"
        after="$(wapt_ini_value "$MERGED_INI" "$key")"
        [ "$before" = "$after" ] || {
            rm -f -- "$MERGED_INI"
            fail "Target runtime setting changed unexpectedly during merge: $key"
        }
    done

    SOURCE_CA_KEY="$BUNDLE/certificates/client-ca/$(basename "$CA_KEY")"
    SOURCE_CA_CERT="$BUNDLE/certificates/client-ca/$(basename "$CA_CERT")"

    MERGED_CA_KEY="$(wapt_ini_value "$MERGED_INI" clients_signing_key)"
    MERGED_CA_CERT="$(wapt_ini_value "$MERGED_INI" clients_signing_certificate)"
    [ -n "$MERGED_CA_KEY" ] || fail "Merged clients_signing_key is empty"
    [ -n "$MERGED_CA_CERT" ] || fail "Merged clients_signing_certificate is empty"
    case "$MERGED_CA_KEY" in /opt/wapt/conf/*) ;; *) fail "Refusing client signing key path outside /opt/wapt/conf: $MERGED_CA_KEY" ;; esac
    case "$MERGED_CA_CERT" in /opt/wapt/conf/*) ;; *) fail "Refusing client signing certificate path outside /opt/wapt/conf: $MERGED_CA_CERT" ;; esac

    TARGET_NGINX_CONF="/etc/nginx/sites-available/wapt.conf"
    [ -f "$TARGET_NGINX_CONF" ] || fail "Target nginx WAPT configuration is missing: $TARGET_NGINX_CONF"
    TARGET_TLS_CERT="$(sed -n -E 's/^[[:space:]]*ssl_certificate[[:space:]]+"?([^";]+)"?;.*/\1/p' "$TARGET_NGINX_CONF" | head -n 1)"
    TARGET_TLS_KEY="$(sed -n -E 's/^[[:space:]]*ssl_certificate_key[[:space:]]+"?([^";]+)"?;.*/\1/p' "$TARGET_NGINX_CONF" | head -n 1)"
    [ -n "$TARGET_TLS_CERT" ] || fail "Unable to determine target nginx TLS certificate path"
    [ -n "$TARGET_TLS_KEY" ] || fail "Unable to determine target nginx TLS key path"
    case "$TARGET_TLS_CERT" in /opt/wapt/waptserver/ssl/*) ;; *) fail "Refusing TLS certificate path outside /opt/wapt/waptserver/ssl: $TARGET_TLS_CERT" ;; esac
    case "$TARGET_TLS_KEY" in /opt/wapt/waptserver/ssl/*) ;; *) fail "Refusing TLS key path outside /opt/wapt/waptserver/ssl: $TARGET_TLS_KEY" ;; esac

    SOURCE_TLS_CERT="$BUNDLE/certificates/server-tls/$(basename "$TLS_CERT")"
    SOURCE_TLS_KEY="$BUNDLE/certificates/server-tls/$(basename "$TLS_KEY")"

    install -d -o wapt -g root -m 0750 /opt/wapt/conf || fail "Unable to secure /opt/wapt/conf"
    install -d -o root -g root -m 0750 /opt/wapt/waptserver/ssl || fail "Unable to secure target TLS directory"

    install -o wapt -g root -m 0640 "$SOURCE_CA_KEY" "$MERGED_CA_KEY" || fail "Unable to restore client signing key"
    install -o wapt -g root -m 0644 "$SOURCE_CA_CERT" "$MERGED_CA_CERT" || fail "Unable to restore client signing certificate"
    install -o root -g root -m 0644 "$SOURCE_TLS_CERT" "$TARGET_TLS_CERT" || fail "Unable to restore server TLS certificate"
    install -o root -g root -m 0600 "$SOURCE_TLS_KEY" "$TARGET_TLS_KEY" || fail "Unable to restore server TLS key"

    install -o wapt -g root -m 0640 "$MERGED_INI" "$TARGET_INI" || fail "Unable to install merged waptserver.ini"
    rm -f -- "$MERGED_INI"

    for key in $RESTORE_KEYS; do
        source_value="$(wapt_ini_value "$SOURCE_INI" "$key")"
        target_value="$(wapt_ini_value "$TARGET_INI" "$key")"
        [ "$source_value" = "$target_value" ] || fail "Restored WAPT identity/policy value mismatch: $key"
    done
    for key in $RUNTIME_KEYS; do
        [ -n "$(wapt_ini_value "$TARGET_INI" "$key")" ] || fail "Target runtime setting missing after merge: $key"
    done

    cmp -s "$SOURCE_CA_KEY" "$MERGED_CA_KEY" || fail "Restored client signing key content mismatch"
    cmp -s "$SOURCE_CA_CERT" "$MERGED_CA_CERT" || fail "Restored client signing certificate content mismatch"
    cmp -s "$SOURCE_TLS_CERT" "$TARGET_TLS_CERT" || fail "Restored TLS certificate content mismatch"
    cmp -s "$SOURCE_TLS_KEY" "$TARGET_TLS_KEY" || fail "Restored TLS key content mismatch"

    [ "$(stat -c '%a|%U|%G' "$TARGET_INI")" = "640|wapt|root" ] || fail "Unexpected waptserver.ini permissions"
    [ "$(stat -c '%a|%U|%G' "$MERGED_CA_KEY")" = "640|wapt|root" ] || fail "Unexpected client signing key permissions"
    [ "$(stat -c '%a|%U|%G' "$MERGED_CA_CERT")" = "644|wapt|root" ] || fail "Unexpected client signing certificate permissions"
    [ "$(stat -c '%a|%U|%G' "$TARGET_TLS_KEY")" = "600|root|root" ] || fail "Unexpected TLS key permissions"
    [ "$(stat -c '%a|%U|%G' "$TARGET_TLS_CERT")" = "644|root|root" ] || fail "Unexpected TLS certificate permissions"

    systemctl is-active --quiet waptserver && fail "waptserver unexpectedly active after configuration/identity restore"
    systemctl is-active --quiet postgresql || fail "PostgreSQL unexpectedly inactive after configuration/identity restore"

    echo
    echo "Historical WAPT service FQDN: ${SOURCE_FQDN:-unknown}"
    echo "Current OS hostname:           $(hostname -f 2>/dev/null || hostname)"
    echo "Package prefix:                ${PACKAGE_PREFIX:-unknown} (informational; not changed by this phase)"
    echo "Target nginx configuration:    preserved"
    ok "WAPT configuration and identity restored and validated"
}


restore_target_repository() {
    echo
    echo "=================================================="
    echo "REPOSITORY PHASE"
    echo "=================================================="

    [ "$REPO_INCLUDED" = "yes" ] || fail "Source backup does not contain repository payload"

    SOURCE_REPO="$BUNDLE/repository/wapt"
    TARGET_REPO="/var/www/wapt"
    [ -d "$SOURCE_REPO" ] || fail "Source repository is missing from extracted bundle"
    [ -d "$TARGET_REPO" ] || fail "Target repository is missing: $TARGET_REPO"

    PRESERVE_SETUP="$TARGET_REPO/waptsetup-tis.exe"
    PRESERVE_DEPLOY="$TARGET_REPO/waptdeploy.exe"
    [ -f "$PRESERVE_SETUP" ] || fail "Target waptsetup-tis.exe is missing; refusing repository replacement"
    [ -f "$PRESERVE_DEPLOY" ] || fail "Target waptdeploy.exe is missing; refusing repository replacement"

    SETUP_SHA_BEFORE="$(sha256sum "$PRESERVE_SETUP" | awk '{print $1}')"
    DEPLOY_SHA_BEFORE="$(sha256sum "$PRESERVE_DEPLOY" | awk '{print $1}')"

    FILTERED_REPO_MANIFEST="$WORKDIR/repository-manifest.final.sha256"
    awk '
        {
            path=$NF
            sub(/^\*/, "", path)
            sub(/^\.\//, "", path)
            if (path != "waptsetup-tis.exe" && path != "waptdeploy.exe")
                print $0
        }
    ' "$REPO_MANIFEST" > "$FILTERED_REPO_MANIFEST" || \
        fail "Unable to build final repository validation manifest"

    SOURCE_PRESERVED_ENTRIES="$(awk '
        {
            path=$NF
            sub(/^\*/, "", path)
            sub(/^\.\//, "", path)
            if (path == "waptsetup-tis.exe" || path == "waptdeploy.exe")
                n++
        }
        END { print n+0 }
    ' "$REPO_MANIFEST")"
    [ "$SOURCE_PRESERVED_ENTRIES" = "2" ] || \
        fail "Expected exactly 2 setup/deploy entries in source repository manifest, got $SOURCE_PRESERVED_ENTRIES"

    echo "Preserved waptsetup-tis.exe SHA256: $SETUP_SHA_BEFORE"
    echo "Preserved waptdeploy.exe SHA256:    $DEPLOY_SHA_BEFORE"

    REPOSITORY_ALREADY_RESTORED="no"
    if (
        cd "$TARGET_REPO" || exit 1
        sha256sum -c "$FILTERED_REPO_MANIFEST"
    ) >/dev/null 2>&1; then
        REPOSITORY_ALREADY_RESTORED="yes"
        warn "Repository payload already matches the source backup except for the two intentionally preserved target executables"
        ok "Repository resume state accepted; 13 GB payload copy will be skipped"
    fi

    if [ "$REPOSITORY_ALREADY_RESTORED" = "no" ]; then
        echo "Replacing historical repository payload while preserving target 7402 setup/deploy executables..."

        # Keep the validated target executables physically in place. Everything else
        # is recreated from the already-validated source repository.
        find "$TARGET_REPO" -mindepth 1 -maxdepth 1 \
            ! -name 'waptsetup-tis.exe' \
            ! -name 'waptdeploy.exe' \
            -exec rm -rf -- {} + || fail "Unable to clear target repository payload"

        COPY_FIFO="$WORKDIR/repository-copy.fifo"
        mkfifo "$COPY_FIFO" || fail "Unable to create repository copy FIFO"

        (
            cd "$TARGET_REPO" || exit 1
            tar -xf "$COPY_FIFO"
        ) &
        REPO_EXTRACT_PID=$!

        (
            cd "$SOURCE_REPO" || exit 1
            tar \
                --exclude='./waptsetup-tis.exe' \
                --exclude='./waptdeploy.exe' \
                -cf "$COPY_FIFO" .
        )
        REPO_CREATE_RC=$?

        wait "$REPO_EXTRACT_PID"
        REPO_EXTRACT_RC=$?
        rm -f -- "$COPY_FIFO"

        [ "$REPO_CREATE_RC" -eq 0 ] || fail "Unable to read source repository payload"
        [ "$REPO_EXTRACT_RC" -eq 0 ] || fail "Unable to extract repository payload into target"
    fi

    [ -f "$PRESERVE_SETUP" ] || fail "Preserved waptsetup-tis.exe disappeared during repository restore"
    [ -f "$PRESERVE_DEPLOY" ] || fail "Preserved waptdeploy.exe disappeared during repository restore"

    SETUP_SHA_AFTER="$(sha256sum "$PRESERVE_SETUP" | awk '{print $1}')"
    DEPLOY_SHA_AFTER="$(sha256sum "$PRESERVE_DEPLOY" | awk '{print $1}')"
    [ "$SETUP_SHA_AFTER" = "$SETUP_SHA_BEFORE" ] || fail "waptsetup-tis.exe changed during repository restore"
    [ "$DEPLOY_SHA_AFTER" = "$DEPLOY_SHA_BEFORE" ] || fail "waptdeploy.exe changed during repository restore"

    chown -R wapt:www-data "$TARGET_REPO" || fail "Unable to set repository ownership"
    find "$TARGET_REPO" -type d -exec chmod 0750 {} + || fail "Unable to set repository directory permissions"
    find "$TARGET_REPO" -type f -exec chmod 0640 {} + || fail "Unable to set repository file permissions"

    echo "Validating restored repository against source per-file SHA256 manifest..."
    (
        cd "$TARGET_REPO" || exit 1
        sha256sum -c "$FILTERED_REPO_MANIFEST"
    ) >/dev/null || fail "Final repository SHA256 validation failed"

    SETUP_SHA_FINAL="$(sha256sum "$PRESERVE_SETUP" | awk '{print $1}')"
    DEPLOY_SHA_FINAL="$(sha256sum "$PRESERVE_DEPLOY" | awk '{print $1}')"
    [ "$SETUP_SHA_FINAL" = "$SETUP_SHA_BEFORE" ] || fail "Final waptsetup-tis.exe SHA256 mismatch"
    [ "$DEPLOY_SHA_FINAL" = "$DEPLOY_SHA_BEFORE" ] || fail "Final waptdeploy.exe SHA256 mismatch"

    FINAL_REPO_FILES="$(find "$TARGET_REPO" -type f | wc -l)"
    EXPECTED_FINAL_REPO_FILES=$((REPO_FILES - SOURCE_PRESERVED_ENTRIES + 2))
    [ "$FINAL_REPO_FILES" = "$EXPECTED_FINAL_REPO_FILES" ] || \
        fail "Final repository file count mismatch: expected $EXPECTED_FINAL_REPO_FILES, got $FINAL_REPO_FILES"

    [ -f "$TARGET_REPO/Packages" ] || fail "Restored repository Packages index is missing"
    PACKAGES_SHA="$(sha256sum "$TARGET_REPO/Packages" | awk '{print $1}')"

    [ "$(stat -c '%a|%U|%G' "$TARGET_REPO")" = "750|wapt|www-data" ] || \
        fail "Unexpected repository root permissions"

    systemctl is-active --quiet waptserver && fail "waptserver unexpectedly active after repository restore"
    systemctl is-active --quiet postgresql || fail "PostgreSQL unexpectedly inactive after repository restore"

    echo
    echo "Repository files:             $FINAL_REPO_FILES"
    echo "Packages SHA256:              $PACKAGES_SHA"
    echo "Preserved waptsetup SHA256:   $SETUP_SHA_FINAL"
    echo "Preserved waptdeploy SHA256:  $DEPLOY_SHA_FINAL"
    ok "Historical repository restored and validated; target setup/deploy executables preserved"
}


validate_and_start_services() {
    echo
    echo "=================================================="
    echo "SERVICE / FQDN / TLS VALIDATION PHASE"
    echo "=================================================="

    TARGET_NGINX_CONF="/etc/nginx/sites-available/wapt.conf"
    [ -f "$TARGET_NGINX_CONF" ] || fail "Target nginx WAPT configuration is missing: $TARGET_NGINX_CONF"

    TARGET_TLS_CERT="$(sed -n -E 's/^[[:space:]]*ssl_certificate[[:space:]]+"?([^";]+)"?;.*/\1/p' "$TARGET_NGINX_CONF" | head -n 1)"
    TARGET_TLS_KEY="$(sed -n -E 's/^[[:space:]]*ssl_certificate_key[[:space:]]+"?([^";]+)"?;.*/\1/p' "$TARGET_NGINX_CONF" | head -n 1)"
    [ -f "$TARGET_TLS_CERT" ] || fail "Target TLS certificate is missing: ${TARGET_TLS_CERT:-unknown}"
    [ -f "$TARGET_TLS_KEY" ] || fail "Target TLS key is missing: ${TARGET_TLS_KEY:-unknown}"

    TLS_PUB_CERT="$(openssl x509 -in "$TARGET_TLS_CERT" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform pem 2>/dev/null)" || \
        fail "Unable to read public key from restored TLS certificate"
    TLS_PUB_KEY="$(openssl pkey -in "$TARGET_TLS_KEY" -pubout -outform pem 2>/dev/null)" || \
        fail "Unable to read public key from restored TLS private key"
    [ "$TLS_PUB_CERT" = "$TLS_PUB_KEY" ] || fail "Restored TLS certificate/private key do not match"
    ok "Restored TLS certificate/private key match"

    WAPT_SERVICE_FQDN="$(openssl x509 -in "$TARGET_TLS_CERT" -noout -subject -nameopt RFC2253 2>/dev/null | \
        sed -n -E 's/^subject=.*CN=([^,]+).*$/\1/p' | head -n 1)"
    [ -n "$WAPT_SERVICE_FQDN" ] || fail "Unable to derive historical WAPT service FQDN from restored TLS certificate CN"
    case "$WAPT_SERVICE_FQDN" in
        *.*) ;;
        *) fail "Restored TLS certificate CN does not look like a FQDN: $WAPT_SERVICE_FQDN" ;;
    esac
    case "$WAPT_SERVICE_FQDN" in
        *[!A-Za-z0-9.-]*) fail "Restored TLS certificate CN contains unsupported FQDN characters: $WAPT_SERVICE_FQDN" ;;
    esac

    TLS_NOT_AFTER="$(openssl x509 -in "$TARGET_TLS_CERT" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')" || \
        fail "Unable to read restored TLS certificate expiry"
    openssl x509 -in "$TARGET_TLS_CERT" -noout -checkend 0 >/dev/null 2>&1 || \
        fail "Restored TLS certificate is already expired"
    ok "Restored TLS certificate is currently valid"

    TARGET_OS_FQDN="$(hostname -f 2>/dev/null || hostname)"
    echo
    echo "Source OS FQDN:       ${SOURCE_FQDN:-unknown}"
    echo "WAPT service FQDN:    $WAPT_SERVICE_FQDN"
    echo "Target OS FQDN:       $TARGET_OS_FQDN"
    echo "TLS certificate ends: $TLS_NOT_AFTER"

    DNS_RESULT=""
    if command -v getent >/dev/null 2>&1; then
        DNS_RESULT="$(getent ahostsv4 "$WAPT_SERVICE_FQDN" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    fi
    if [ -n "$DNS_RESULT" ]; then
        echo "Current DNS IPv4:     $DNS_RESULT"
        warn "DNS result is informational only; this restore does not change DNS or authorize production-client reconnection"
    else
        echo "Current DNS IPv4:     <not resolved from this target>"
        warn "Historical WAPT service FQDN does not currently resolve here; this is acceptable for an isolated DR validation"
    fi

    command -v nginx >/dev/null 2>&1 || fail "nginx command is unavailable"
    nginx -t >/dev/null 2>&1 || fail "Target nginx configuration test failed"
    ok "nginx configuration test passed"

    systemctl is-active --quiet postgresql || fail "PostgreSQL is not active before WAPT service start"
    systemctl is-active --quiet nginx || fail "nginx is not active before WAPT service start"

    echo
    echo "Starting/validating WAPT application services..."
    if systemctl is-active --quiet waptserver; then
        warn "waptserver is already active; accepting service-resume state"
    else
        systemctl start waptserver || fail "Unable to start waptserver"
    fi

    WAPTSERVER_READY="no"
    for _attempt in 1 2 3 4 5 6 7 8 9 10; do
        if systemctl is-active --quiet waptserver; then
            WAPTSERVER_READY="yes"
            break
        fi
        sleep 1
    done
    [ "$WAPTSERVER_READY" = "yes" ] || fail "waptserver did not become active within 10 seconds"
    ok "waptserver is active"

    if systemctl list-unit-files wapttasks.service 2>/dev/null | grep -q '^wapttasks\.service'; then
        if systemctl is-active --quiet wapttasks; then
            warn "wapttasks is already active; accepting service-resume state"
        else
            systemctl start wapttasks || fail "Unable to start wapttasks"
        fi

        WAPTTASKS_READY="no"
        for _attempt in 1 2 3 4 5; do
            if systemctl is-active --quiet wapttasks; then
                WAPTTASKS_READY="yes"
                break
            fi
            sleep 1
        done
        [ "$WAPTTASKS_READY" = "yes" ] || fail "wapttasks did not become active within 5 seconds"
        ok "wapttasks is active"
    else
        warn "wapttasks.service is not installed; no wapttasks start attempted"
    fi

    command -v curl >/dev/null 2>&1 || fail "curl command is unavailable for local HTTPS validation"
    echo
    echo "Waiting for local WAPT HTTPS readiness (maximum 30 seconds)..."
    LOCAL_HTTPS_CODE=""
    HTTPS_READY="no"
    for _attempt in $(seq 1 30); do
        LOCAL_HTTPS_CODE="$(curl -k -sS -o /dev/null -w '%{http_code}' \
            --resolve "${WAPT_SERVICE_FQDN}:443:127.0.0.1" \
            "https://${WAPT_SERVICE_FQDN}/" 2>/dev/null || true)"
        case "$LOCAL_HTTPS_CODE" in
            2??|3??|401|403)
                HTTPS_READY="yes"
                break
                ;;
        esac
        sleep 1
    done
    [ "$HTTPS_READY" = "yes" ] || \
        fail "Local WAPT HTTPS endpoint did not become ready within 30 seconds (last status: ${LOCAL_HTTPS_CODE:-none})"
    ok "Local HTTPS validation passed with HTTP status $LOCAL_HTTPS_CODE"

    echo
    echo "SERVICE / FQDN / TLS VALIDATION PASSED"
    echo "The restored WAPT service is running locally with the historical TLS identity."
    echo
    echo "=================================================="
    echo "PRE-PRODUCTION CUTOVER BARRIER"
    echo "=================================================="
    echo "Historical WAPT service FQDN: $WAPT_SERVICE_FQDN"
    echo "Current target OS FQDN:       $TARGET_OS_FQDN"
    echo "Current DNS IPv4:             ${DNS_RESULT:-<not resolved>}"
    echo
    echo "DO NOT reconnect production clients yet."
    echo "DO NOT change production DNS as part of this script."
    echo "Before production cutover, explicitly validate that:"
    echo "  1. $WAPT_SERVICE_FQDN resolves to the intended restored production server;"
    echo "  2. network/firewall/ACL rules permit the intended client traffic;"
    echo "  3. the TLS identity presented for $WAPT_SERVICE_FQDN is the intended restored/renewed certificate;"
    echo "  4. the WAPT console is used to regenerate waptagent.exe with the intended authorized certificate(s)."
    echo
    warn "TLS certificate renewal must be planned before: $TLS_NOT_AFTER"
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

for tool in tar sha256sum awk grep sed find wc mktemp mkfifo pg_restore df stat sort install cmp hostname head openssl curl; do
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

    RESTORE_STATE="normal"
    if [ "$TARGET_WAPTSERVER_ACTIVE" = "no" ]; then
        TARGET_PUBLIC_TABLE_COUNT="$(cd / && runuser -u postgres -- \
            psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
            "SELECT count(*) FROM pg_tables WHERE schemaname='public';" \
            2>/dev/null)" || fail "Unable to assess interrupted-restore database state"
        if [ "$TARGET_PUBLIC_TABLE_COUNT" = "0" ]; then
            RESTORE_STATE="interrupted-empty"
            warn "Interrupted restore state detected: waptserver inactive and target database has 0 public tables"
            ok "Interrupted empty state accepted; database restore will restart from scratch"
        else
            if validate_post_database_state; then
                RESTORE_STATE="post-database"
                warn "Post-database restore state detected: marker, ownership, ACL and source table counts all match"
                ok "Post-database state accepted; destructive database restore will be skipped"
            else
                RESTORE_STATE="interrupted-partial"
                warn "Interrupted partial restore state detected: waptserver inactive and database does not fully match source backup"
                ok "Interrupted partial state accepted; database restore will restart from scratch"
            fi
        fi
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

    case "$RESTORE_STATE" in
        normal)
            TARGET_DB_MARKER="$(cd / && runuser -u postgres -- \
                psql -p "$TARGET_PG_PORT" -d wapt -Atqc \
                "SELECT value FROM serverattribs WHERE key='db_version';" \
                2>/dev/null)" || fail "Unable to read target WAPT database marker"
            [ -n "$TARGET_DB_MARKER" ] || fail "Target WAPT database marker is empty"
            ;;
        interrupted-empty)
            TARGET_DB_MARKER="<interrupted-empty>"
            warn "Target DB marker check skipped for accepted empty interrupted-restore state"
            ;;
        interrupted-partial)
            TARGET_DB_MARKER="<interrupted-partial>"
            warn "Target DB marker check skipped for accepted partial interrupted-restore state"
            ;;
        post-database)
            TARGET_DB_MARKER="$POST_DB_MARKER"
            ;;
    esac

    echo
    echo "Target Debian:          $TARGET_DEBIAN"
    echo "Target WAPT server:     $TARGET_WAPT"
    echo "Target WAPT setup:      $TARGET_SETUP"
    echo "Target PostgreSQL:      $TARGET_PG_VERSION"
    echo "Target PG cluster:      $TARGET_PG_MAJOR/$TARGET_PG_CLUSTER"
    echo "Target PostgreSQL port: $TARGET_PG_PORT"
    echo "Target DB owner:        $TARGET_DB_OWNER"
    echo "Target DB marker:       $TARGET_DB_MARKER"
    echo "Restore state:          $RESTORE_STATE"
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

    if [ "$RESTORE_STATE" = "post-database" ]; then
        echo
        echo "DATABASE RESTORE SKIPPED"
        echo "A validated post-database restore state was detected."
        echo "The already-restored WAPT database will not be replaced again."
    else
        if [ "$RESTORE_STATE" = "interrupted-empty" ] || [ "$RESTORE_STATE" = "interrupted-partial" ]; then
            echo
            echo "DATABASE RESTORE RESUME"
            echo "Interrupted database state detected; the target database will be recreated from scratch."
        fi
        restore_target_database
        echo
        echo "DATABASE RESTORE PASSED"
        echo "The target WAPT database has been replaced and validated."
    fi

    restore_target_configuration_identity

    echo
    echo "CONFIGURATION / IDENTITY RESTORE PASSED"
    echo "Historical WAPT identity and policy have been restored onto the target runtime."

    restore_target_repository

    echo
    echo "REPOSITORY RESTORE PASSED"
    echo "Historical repository payload and Packages index have been restored."
    echo "Target waptsetup-tis.exe and waptdeploy.exe were preserved in place and SHA256-validated."
    echo "waptserver/wapttasks remain stopped intentionally."
    echo "Target nginx configuration was preserved."
    echo "Safety backup retained at: $SAFETY_ARCHIVE"

    validate_and_start_services

    echo
    echo "RESTORE VALIDATION PASSED"
    echo "Database, configuration/identity, repository, TLS identity and local WAPT service startup are validated."
    echo "Production DNS/client reconnection remains behind the explicit pre-production cutover barrier."
    exit 3
fi
