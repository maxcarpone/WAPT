# WAPT Debian 10 Disaster Recovery

## 1. Purpose and scope

This document is the validated disaster-recovery procedure for a WAPT
Community server running the Debian 10 / WAPT 1.8.2 lineage.

The validated recovery model is a service-identity transplant onto a fresh
target installation. It is not a clone of the source operating system.

The restore preserves the logical WAPT service identity and data required for
client continuity, including:

- the WAPT PostgreSQL database;
- `server_uuid`, `secret_key` and `wapt_password`;
- the validated WAPT identity and policy settings;
- the client CA certificate and key when present;
- the WAPT HTTPS/TLS certificate and key;
- the historical WAPT repository and `Packages` index.

The target operating-system hostname does not have to be identical to the
historical server hostname. The historical WAPT service FQDN, DNS, TLS and
client connectivity requirements are handled separately during cutover.

The package-signing private key used by administrators is an external asset.
It is not included in the server DR backup.

## 2. Validated DR tooling

The Debian 10 DR procedure is frozen around the following validated tools:

### Backup V1.0

- script: `tools/waptserver-backup.sh`
- version: `1.0`
- commit: `226b2cc1`
- SHA256:
  `db8f75aa04fad3e7aa1419e446ddcf3fa19716565237e9ef3a7bde3a5fd8eede`

A normal full backup includes the PostgreSQL database, WAPT configuration,
certificates, repository and validation metadata.

### Restore V1.0

- script: `tools/waptserver-restore.sh`
- version: `1.0`
- commit: `50246dd1f95036ebb0b2a7cd27004deadac5a76a`
- tag: `server-buster-restore-v1.0`
- SHA256:
  `06ff15a4b12b1c92b8f7885a5244e64a1859427093fbfcc19a986b77acdd2270`

Restore V1.0 is the validated V0.7.2 implementation promoted without any
functional change to the restore logic.

## 3. Source server backup

Run the backup tool as `root` on the source WAPT server.

### 3.1 Precheck

A standalone non-destructive precheck can be run first:

```bash
cd /git/waptdev
tools/waptserver-backup.sh precheck
```

Do not continue if the result is not:

```text
[ OK ] PRECHECK PASSED
```

The `backup` and `backup-no-repository` modes also run this precheck
automatically and abort on a blocking failure.

### 3.2 Full DR backup

The normal and preferred DR backup is:

```bash
cd /git/waptdev
tools/waptserver-backup.sh backup
```

The backup root is:

```text
/var/www/wapt-backups
```

For a full backup, the script requires enough free space on that filesystem
for one repository staging copy, the final tar archive and a 2 GiB safety
margin:

```text
required free space = 2 * repository size + 2 GiB
```

Temporary staging is created on the backup filesystem itself, not in `/tmp`.

A successful run ends with:

```text
[ OK ] BACKUP PASSED
Final archive       : /var/www/wapt-backups/wapt-dr-<hostname>-<timestamp>.tar
Archive SHA256      : <sha256>
Repository included : YES
```

The administrator-visible backup artifacts are:

```text
wapt-dr-<hostname>-<timestamp>.tar
wapt-dr-<hostname>-<timestamp>.tar.sha256
```

The extracted staging directory is removed only after the final archive has
been created and validated.

### 3.3 Backup without repository payload

If the repository payload must be transferred separately:

```bash
cd /git/waptdev
tools/waptserver-backup.sh backup-no-repository
```

This mode does not include the repository files in the archive. It still
includes `metadata/repository-manifest.sha256`, which records the SHA256 of
each repository file for subsequent validation.

A `backup-no-repository` archive is not by itself a complete DR backup. The
repository payload must also be preserved and transferred separately.

### 3.4 Backup integrity and contents

The backup script validates the PostgreSQL dump with `pg_restore -l`, creates
a per-file repository SHA256 manifest, creates and verifies the internal
`SHA256SUMS`, and validates the final tar archive.

A full backup contains:

```text
wapt-dr-<hostname>-<timestamp>/
|-- manifest.ini
|-- SHA256SUMS
|-- database/wapt.dump
|-- config/waptserver.ini
|-- config/nginx/wapt.conf
|-- certificates/client-ca/
|-- certificates/server-tls/
|-- repository/wapt/
`-- metadata/
    |-- system.txt
    |-- packages.txt
    |-- database.txt
    |-- repository.txt
    `-- repository-manifest.sha256
```

The bundle is normalized to `root:root`, with directories mode `0700` and
files mode `0600`. The final `.tar` and `.tar.sha256` are also mode `0600`.

Before transferring or using a DR archive, verify its external checksum:

```bash
cd /var/www/wapt-backups
sha256sum -c wapt-dr-<hostname>-<timestamp>.tar.sha256
```

The result must report `OK`. A checksum failure is a STOP condition: do not
use that archive for restore.

## 4. Target server prerequisites

The validated recovery target is a fresh Debian 10 WAPT installation prepared
with the intended target WAPT packages before historical data is restored.

The target must already have:

- `tis-waptserver` installed;
- `tis-waptsetup` installed;
- PostgreSQL installed and active;
- a WAPT database named `wapt`;
- the `wapt` database owned by PostgreSQL role `wapt`;
- exactly one online PostgreSQL cluster containing the `wapt` database;
- that PostgreSQL cluster owned by `postgres`;
- the target WAPT configuration and nginx configuration created by the target
  installation.

The restore tool requires the following commands on the target:

```text
dpkg-query
pg_lsclusters
psql
pg_dump
pg_restore
dropdb
createdb
runuser
systemctl
```

The target operating-system hostname does not have to match the historical
WAPT server hostname.

Do not reconnect the target to production clients at this stage. Historical
WAPT service FQDN, DNS, firewall, TLS and client reconnection are separate
cutover requirements described later in this procedure.

### 4.1 Validate the DR archive

Before starting a restore, run the non-destructive archive check as `root`:

```bash
cd /git/waptdev
tools/waptserver-restore.sh --check /path/to/wapt-dr-<hostname>-<timestamp>.tar
```

The corresponding `.tar.sha256` file must be present beside the archive.

A successful check ends with:

```text
CHECK PASSED
No target WAPT data was modified.
The `--restore` mode repeats these archive validations before any target or
destructive phase. Running `--check` separately is therefore a recommended
non-destructive preflight, not a technical prerequisite for `--restore`.
```

Do not proceed to `--restore` if `--check` fails.

### 4.2 Automatic target safety backup

When `--restore` is started and the restore-target precheck succeeds, the tool
creates a lightweight safety backup of the current target before replacing
the WAPT database.

The safety backup is stored as:

```text
/var/www/wapt-backups/wapt-target-safety-<hostname>-<timestamp>.tar
```

It preserves the target WAPT database, WAPT configuration, server TLS
directory, nginx WAPT configuration when present, target package-owned
`waptsetup-tis.exe` and `waptdeploy.exe` when present, and target metadata.

The repository package payload is intentionally not copied into this safety
backup.

The safety archive is structurally validated and retained if the subsequent
restore proceeds.

## 5. Restore procedure

The restore operation is destructive. An explicit `--check` is recommended
first as a non-destructive preflight. The `--restore` mode repeats the archive
validations itself before validating or modifying the target.

Start the restore with:

```bash
cd /git/waptdev
tools/waptserver-restore.sh --restore /path/to/wapt-dr-<hostname>-<timestamp>.tar
```

The restore tool first validates the target and creates the lightweight target
safety backup described in section 4.

A successful safety-backup phase reports:

```text
[ OK ] Target safety backup created and structurally validated
SAFETY BACKUP PASSED
```

Do not manually stop PostgreSQL before running the restore. The tool controls
the WAPT application services while PostgreSQL remains active.

### 5.1 Database restore

During the destructive database phase, the tool stops `waptserver` and
`wapttasks` when present, while keeping PostgreSQL active.

The target `wapt` database is recreated with owner `wapt`, the default
`public` schema is removed, and the historical custom-format PostgreSQL dump
is restored with `pg_restore --no-owner`.

The tool then applies targeted ownership and schema corrections:

- database `wapt` owned by `wapt`;
- schema `public` owned by `wapt`;
- `USAGE` and `CREATE` on schema `public` granted to `wapt`;
- restored public tables owned by `wapt`;
- restored public sequences owned by `wapt`.

It validates the restored database marker and the essential table counts for:

```text
hostgroups
hostpackagesstatus
hosts
hostsoftwares
packages
waptusers
```

A successful phase reports:

```text
DATABASE RESTORE PASSED
The target WAPT database has been replaced and validated.
```

The restore tool can also recognize validated interrupted states. An empty or
partial interrupted database is recreated from scratch. If a validated
post-database state already matches the source marker, ownership, ACL and
essential table counts, the destructive database restore is skipped.

### 5.2 Configuration and WAPT identity restore

The historical WAPT identity and policy are merged into the target
`/opt/wapt/conf/waptserver.ini`.

The following historical values are restored:

```text
allow_unauthenticated_connect
allow_unauthenticated_registration
clients_signing_certificate
clients_signing_key
secret_key
server_uuid
wapt_password
```

The target installation remains authoritative for runtime and technical
settings, including:

```text
chdir
gid
http-socket
processes
uid
wapt_folder
wapt_huey_db
wapt_user
waptwua_folder
wsgi
master
enable-threads
max-requests
```

The historical client CA certificate and key are restored to the paths
declared by the merged target configuration.

The historical HTTPS/TLS certificate and key are restored to the TLS paths
declared by the target nginx configuration. The target nginx WAPT
configuration itself is preserved.

A successful phase reports:

```text
CONFIGURATION / IDENTITY RESTORE PASSED
Historical WAPT identity and policy have been restored onto the target runtime.
```

### 5.3 Repository restore

A normal automated restore requires a DR backup containing the repository
payload.

The historical repository is restored into:

```text
/var/www/wapt
```

Two target package-owned artifacts are deliberately preserved instead of
being replaced by their historical copies:

```text
/var/www/wapt/waptsetup-tis.exe
/var/www/wapt/waptdeploy.exe
```

Their SHA256 values are recorded before repository replacement and verified
again afterwards.

All other repository content is validated against the per-file SHA256
manifest stored in the DR backup.

Final repository permissions are normalized to:

```text
directories: 0750 wapt:www-data
files:       0640 wapt:www-data
```

The `Packages` index must be present after restore.

If the repository already matches the historical source, except for the two
intentionally preserved target executables, the tool accepts that resume state
and skips copying the repository payload again.

A successful phase reports:

```text
REPOSITORY RESTORE PASSED
Historical repository payload and Packages index have been restored.
Target waptsetup-tis.exe and waptdeploy.exe were preserved in place and SHA256-validated.
```

At this point `waptserver` and `wapttasks` intentionally remain stopped. The
tool then proceeds automatically to the final service, FQDN and TLS validation
phase described in section 6.

## 6. Post-restore validation

The restore tool performs the final validation automatically after the
database, configuration/identity and repository phases.

### 6.1 TLS identity

The restored server TLS certificate and private key must match.

The tool also verifies that the restored certificate is currently valid and
derives the historical WAPT service FQDN from its certificate CN.

The source operating-system FQDN, historical WAPT service FQDN and target
operating-system FQDN are reported separately. They are not required to be
identical.

DNS resolution of the historical WAPT service FQDN is informational during
the isolated DR validation. The restore tool does not modify DNS.

### 6.2 nginx and WAPT services

The target nginx configuration is validated with:

```bash
nginx -t
```

PostgreSQL and nginx must be active before the WAPT application services are
started.

The tool starts or validates `waptserver`, allowing up to 10 seconds for the
service to become active.

If `wapttasks.service` is installed, it is also started or validated, with up
to 5 seconds allowed for it to become active.

### 6.3 Local HTTPS validation

The restored WAPT service is tested locally through the historical WAPT
service FQDN without depending on production DNS.

The tool maps that FQDN to `127.0.0.1` for the local HTTPS request and waits
up to 30 seconds for the endpoint to become ready.

HTTP 2xx, 3xx, 401 and 403 responses are accepted as proof that the local
HTTPS endpoint is responding.

A successful final validation reports:

```text
SERVICE / FQDN / TLS VALIDATION PASSED
The restored WAPT service is running locally with the historical TLS identity.

RESTORE VALIDATION PASSED
Database, configuration/identity, repository, TLS identity and local WAPT service startup are validated.
```

`RESTORE VALIDATION PASSED` confirms the isolated technical restore. It does
not authorize production DNS changes or production-client reconnection.

The restore script intentionally exits with status `3` after this successful
restore-validation result. For this tool, exit status `3` following
`RESTORE VALIDATION PASSED` represents the completed restore with the
pre-production cutover barrier still in effect; it must not be interpreted as
a restore failure.

## 7. Pre-production cutover barrier

A successful restore validation does not authorize production-client
reconnection.

Before production cutover, explicitly validate all of the following:

1. The historical WAPT service FQDN resolves to the intended restored
   production server.
2. Network, firewall and ACL rules permit the intended WAPT client traffic.
3. The TLS identity presented for the historical WAPT service FQDN is the
   intended restored or renewed certificate.
4. The authorized WAPT package certificates have been reviewed and are the
   intended certificates for the restored environment.
5. The external administrator package-signing private key and certificate are
   available. This private key is not part of the server DR backup.
6. Regenerate `waptagent.exe` from the current target WAPT console with the
   intended authorized certificate(s).
7. Generate and publish the current `<prefix>-waptupgrade` package for the
   target WAPT version.
8. Validate at least one authentic historical client against the restored
   server before broad production reconnection.

The restore tool does not change production DNS and must not be used as an
implicit authorization to reconnect clients.

For the validated historical environment, the restored TLS certificate for
the WAPT service FQDN expires on 2027-12-03. Its renewal or replacement must
be planned before that date while preserving the WAPT service FQDN semantics.

## 8. Client reconnection and upgrade

Production clients must remain disconnected until every item in the
pre-production cutover barrier has been validated.

Before broad reconnection:

1. Regenerate `waptagent.exe` from the current target WAPT console using the
   intended authorized certificate(s).
2. Generate and publish the current `<prefix>-waptupgrade` package.
3. Select at least one authentic historical client for controlled validation.
4. Confirm that the client trusts and reaches the restored WAPT service through
   the historical service FQDN.
5. Validate the complete client upgrade before reconnecting the wider client
   population.

The historical Debian 10 DR validation successfully tested an authentic WAPT
1.8.2.7393 client against the restored server and upgraded it to WAPT
1.8.2.7402. The resulting client service was running and the client was
reachable from the console.

Do not use `wapt-get -d` or `wapt-get --dry-run install` as a preflight for a
real WAPT agent self-upgrade. During validation, this mode could incorrectly
record the upgrade package as installed in the client's local database without
performing the actual upgrade.

If such a diagnostic dry-run has already altered the local package state,
`wapt-get -f` / `--force` may be required for the subsequent real installation.

Successful validation of one historical client is a mandatory gate before
broad production-client reconnection.

## 9. Certificates, trust and external assets

Several distinct trust mechanisms are involved in a restored WAPT
environment. They must not be confused.

### 9.1 WAPT server HTTPS/TLS identity

The DR backup contains the WAPT server HTTPS/TLS certificate and private key.

Restore V1.0 restores this historical TLS identity while preserving the target
nginx configuration. The certificate and private key are validated as a
matching pair before the restored service is accepted.

The TLS certificate identifies the historical WAPT service FQDN used by
clients. Its lifecycle is independent from WAPT package signing.

For the validated historical environment, the restored TLS certificate
expires on 2027-12-03 and must be renewed or replaced before that date.

### 9.2 WAPT client CA identity

The DR backup contains the client CA certificate and private key referenced by
the historical WAPT server configuration when present.

Restore V1.0 restores these files together with the corresponding
`clients_signing_certificate` and `clients_signing_key` configuration values.

These assets participate in WAPT server/client identity and must not be
confused with the administrator package-signing certificate.

### 9.3 WAPT package-signing identity

The administrator package-signing private key is an external administrative
asset and is not included in the server DR backup.

Before production-client reconnection, verify that the intended package-signing
certificate is authorized by the restored environment and that its associated
private key is available to the administrator or WAPT console that will sign
packages.

This signing identity is required when regenerating `waptagent.exe` and when
building and signing the current `<prefix>-waptupgrade` package.

### 9.4 Windows Authenticode

Windows Authenticode signing is a separate trust mechanism from WAPT package
signing.

The validated WAPT 1.8.2.7402 Windows reconstruction used a temporary
self-signed laboratory Authenticode certificate. That certificate is suitable
for the validated laboratory milestone only and is not the final production
distribution-signing strategy.

The production Authenticode strategy must be explicitly reviewed before the
consolidated autonomous release.

## 10. Known limitations and operational notes

This procedure documents the validated Debian 10 disaster-recovery path for
the WAPT 1.8.2 lineage. It is not yet the final consolidated WAPT 1.8.3
procedure.

The following operational constraints apply:

- Restore V1.0 performs a service-identity and data transplant onto an already
  installed target WAPT server. It does not clone or recreate the source
  operating system.
- The target operating-system hostname and IP address may differ from the
  historical server. Production DNS, routing, firewall and ACL changes remain
  explicit administrator responsibilities.
- Automated repository restoration requires a backup containing the repository
  payload. A `backup-no-repository` archive requires separate handling and
  validation of the repository payload.
- The target nginx WAPT configuration remains authoritative. The historical
  nginx configuration stored in the backup is retained as a reference only.
- Target `waptsetup-tis.exe` and `waptdeploy.exe` are deliberately preserved
  during historical repository restoration.
- Historical `waptagent.exe` must not be treated as the final agent for the
  restored target. Regenerate it from the current target console with the
  intended authorized certificate(s).
- The administrator WAPT package-signing private key is not contained in the
  server DR backup and must be protected and managed separately.
- Restore V1.0 derives the historical WAPT service FQDN from the restored TLS
  certificate CN. A future backup/restore format should record the service
  FQDN explicitly instead of relying on this derivation.
- The validated historical TLS certificate expires on 2027-12-03.
- The successful restore exit status `3` is intentional and represents a
  completed technical restore that remains behind the pre-production cutover
  barrier.
- Production reconnection requires a controlled historical-client validation
  before broad client access is restored.

The validated Backup V1.0 and Restore V1.0 tools are frozen Debian 10 DR
milestones. Functional changes to either tool require a new version and a new
validation cycle.
