# WAPT 1.8.2 Modernization â€” Technical Checkpoint

**Checkpoint date:** 2026-09-21
**Purpose:** authoritative save-state for resuming the WAPT Community modernization project without replaying the historical conversation.

## 1. Project objective

Modernize the WAPT 1.8.2 Community codebase while preserving compatibility with existing deployments and a reproducible migration path.

Production context:

- 9 existing WAPT servers.
- Historical production OS: Debian 10.13 Buster.
- Historical production WAPT: 1.8.2.7393.
- Transitional Python 2 compatibility is intentional; Python 3 modernization is a later phase.
- Community edition is the target; Enterprise is not.

Target migration concept:

1.  Debian 10 / WAPT 7393.
2.  Debian 10 / autonomous rebuilt Python-2-compatible WAPT.
3.  Debian 11.
4.  Debian 12 transitional runtime/package.
5.  Later Debian 13 / Python 3 modernization.

## 2. Main WAPT repository â€” authoritative state

Repository:

``` text
https://github.com/maxcarpone/WAPT
```

Windows working tree:

``` text
C:\git\waptdev
```

Branch:

``` text
branch-1.8.2
```

Authoritative HEAD before this checkpoint commit:

``` text
895cb7597 Fix read-only SoGrid data loading
```

Natural Git commit count:

``` text
7402
```

Remote before publishing this checkpoint is still:

``` text
origin/branch-1.8.2 = 2ea908bf6 Add WAPT technical checkpoint
```

Therefore the following validated technical commits still need to be pushed with the checkpoint:

``` text
532404ef0 Fix VC90 CRT manifest for 9.0.30729.6161
06f71f280 Update SoGrid Lazarus 1.8 dependencies
895cb7597 Fix read-only SoGrid data loading
```

Historical reference commits:

``` text
75a5de09  historical build 7393
566bcad8  historical build 7394
4bbf306a  historical build 7395
3882380da Fix Community waptconsole build without Enterprise units
74bfc5ef6 Fix waptexit build with Lazarus 1.8.2
0ea123e0b Use WAPT-compatible SoGrid fork
2ea908bf6 Add WAPT technical checkpoint
532404ef0 VC90 CRT manifest fix / natural build 7400
06f71f280 SoGrid Lazarus package dependency fix / natural build 7401
895cb7597 read-only SoGrid fix / natural build 7402
```

### Build-number mechanism â€” RESOLVED

The historical mechanism was traced through `create_version_full.py`, `lazbuild.py` and `waptdevutils.py`.

Rule:

``` text
WAPT build number = number of Git commits reachable from the commit being built
```

Historical verification:

``` text
7393 commit -> count 7393
7394 commit -> count 7394
7395 commit -> count 7395
895cb7597 -> count 7402
```

Current release version:

``` text
1.8.2.7402
```

Do not force arbitrary build numbers. Finalize source first, then let the historical Git-count mechanism determine the build number.

A future real 1.8.3/1.9 release requires changing the canonical semantic version (`__version__`); the fourth component remains the Git commit count and does not reset.

## 3. Current Git working tree state

After restoring Lazarus-generated `.lpi`, `.ico` and `waptconsole.sha256` side effects:

``` text
 M submodules/pltis_synapse
```

This is the expected state.

`pltis_synapse` is intentionally checked out at a public commit different from the parent repository's historical/private gitlink. Do not â€œfixâ€ or commit it accidentally.

Submodule snapshot before checkpoint:

``` text
-540d1814813f2cd5a2445910989f50cfaf1a9228 submodules/pltis_sogrid
+14589d4b7b5886242552021e5a1a637b1ea4c82f submodules/pltis_synapse (heads/master)
```

The `-` on SoGrid means it is not initialized through normal submodule metadata in that checkout; the parent gitlink itself is correct.

Never use:

``` text
git add .
```

## 4. SoGrid â€” FINAL 7402 STATE

Fork:

``` text
https://github.com/maxcarpone/pltis_sogrid
```

Branch:

``` text
wapt-1.8.2-compat
```

Compatibility reconstruction:

``` text
68f6e98a63ce9db1769053ed5cbdef7e5d51509e
```

Lazarus package dependency fix:

``` text
e2fa563...
```

Final read-only LoadData fix:

``` text
540d1814813f2cd5a2445910989f50cfaf1a9228
Fix loading read-only SoGrid data
```

Parent WAPT commit recording the final SoGrid gitlink:

``` text
895cb7597 Fix read-only SoGrid data loading
```

### Root cause and final fix

WAPTConsole's Edit Machine dialog showed an empty `Paquets disponibles` grid even though Python package search returned the expected package.

`uviseditpackage.GridPackages` uses `toReadOnly`. VirtualTrees' `SetChildCount` is a no-op while `toReadOnly` is set. The final fix in `TSOGrid.LoadData` temporarily removes `toReadOnly` while clearing/loading `RootNodeCount`, then restores it before focus restoration.

The nil-data branch similarly removes/re-adds `toReadOnly` around `Clear`.

Runtime validation in the real WAPTConsole confirmed that `deb10-waptupgrade` is visibly displayed in the available-packages grid.

### Historical confirmation

The original developers restored missing history in the official SoGrid repository. The exact historical commit was recovered:

``` text
3dfe40c453350c9db1eb025c9b9db9402552092a
Fix loading data in grid when toReadOnly is set Prevent duplicated rows when KeyFieldsNames is set
```

It is reachable from official `origin/master`.

The historical `LoadData` implementation uses the same temporary `toReadOnly` removal/restoration mechanism independently reconstructed for 7402.

Do not cherry-pick the whole historical commit: it also changes `AddRows`, `NodesForKey`, `Clear`, etc., while the reconstructed branch contains later/different API changes. The final 7402 LoadData patch is runtime validated and historically confirmed.

**Freeze SoGrid for 7402.** Do not rework its history before final release validation. A later cleanup/rebase against restored official history is optional.

### Encoding/EOL

The working `sogrid.pas` uses CRLF. Do not normalize the whole file and do not use PowerShell `Set-Content` on legacy Pascal files where encoding/EOL matter.

## 5. Other Lazarus submodules

Synapse expected historical/private gitlink differs from the public checkout in use:

``` text
public checkout: 14589d4b7b5886242552021e5a1a637b1ea4c82f
```

The divergence is intentional. Do not commit it accidentally.

LCL Extensions and Enterprise may appear uninitialized (`-` prefix). Enterprise is not part of this Community reconstruction.

Do not fork every `pltis_*` dependency blindly; only make a dependency reproducible when needed.

## 6. Debian 12 transitional Python 2 runtime

Reference host:

``` text
Debian GNU/Linux 12.15 (bookworm)
Kernel 6.1.0-32-amd64
amd64 / x86_64
GCC 12.2.0
GNU Make 4.3
Python 3.11.2
OpenSSL 3.0.20
```

Python 2.7.18 was built from source.

Consolidated runtime:

``` text
/git/waptdev/build/python2-runtime-server
```

Key validated legacy packages include:

``` text
cryptography==2.5
pyOpenSSL==19.0.0
asn1crypto==1.5.1
cffi==1.11.5
dnspython==1.16.0
Flask==1.1.1
Flask-Login==0.4.1
Flask-SocketIO==4.2.1
Flask-Babel==0.11.2
Babel==2.9.1
eventlet==0.25.1
gevent==1.4.0
greenlet==0.4.15
passlib==1.7.1
six==1.16.0
future==0.16.0
enum34==1.1.10
chardet==4.0.0
certifi==2021.10.8
setproctitle==1.1.10
```

Additional resolved dependencies include `requests`, `psutil`, and `netifaces`.

Known non-blocking absence:

``` text
lzma
```

Validated:

- Python 2 SSL works with OpenSSL 3.0.20.
- `cryptography==2.5` works with the WAPT verification patch.
- `pyOpenSSL==19.0.0` imports.
- `waptcrypto` functional API loads.
- CA / CSR / client certificate / signing / verification test passed.
- `waptserver` imports.
- final runtime report: `All WAPT runtime tests passed.`

## 7. Debian server package state

Bookworm reference build:

``` text
branch: build/debian12-bookworm
commit: 5da9f66b
```

Buster reference build:

``` text
branch: build/debian10-buster
commit: 907d4e78
```

Validated Buster package:

``` text
/git/waptdev/waptserver/deb/tis-waptserver-1.8.2.7397-907d4e78-debian-10-amd64.deb
```

SHA256:

``` text
7445288003d062e7a8afa29d1b8395cdf0b3705b0bc526d49b3a17e214a37733
```

Installed runtime:

``` text
/opt/wapt/bin/python -> Python 2.7.18
```

## 8. Debian 10 lab server

``` text
hostname: wapt-deb10
FQDN: wapt-deb10.genevoix-signoret-vinci.fr.lan
IP: 192.168.220.12/22
gateway: 192.168.223.254
```

Installed:

- rebuilt Buster WAPT server package;
- PostgreSQL 11;
- nginx.

Validated:

- WAPT server active/enabled on localhost:8080;
- nginx on 80/443;
- PostgreSQL 11 on localhost:5432;
- WAPT role/database present;
- HTTPS portal reachable;
- unauthenticated registration mode selected (historical WAPT 1.3 behavior).

Fresh DB marker discrepancy remains:

``` text
fresh lab: OK (1.8.2.0)
historical production screenshot: OK (1.8.2.1)
```

Do not hand-edit the DB marker. This is deferred server cleanup.

## 9. Portal agent publication â€” RESOLVED FOR LAB

The lab portal originally fell back to an old historical WAPT setup when no local setup was published.

After the final Windows release work, downloading the agent through the normal web interface produced:

``` text
waptagent.exe
FileVersion    1.8.2.7402
ProductVersion 1.8.2.7402
ProductName    WAPTAgent
```

This exact portal-delivered agent was used for the successful VM105 production-style migration test described below.

For production, preserve the requirement that the server serves the locally validated setup/agent and does not depend on an obsolete external fallback.

## 10. Windows build workstation

``` text
Windows 11 25H2 AMD64
Repo: C:\git\waptdev
Git: 2.55.0.windows.5
Python: C:\Python27\python.exe (2.7.18 x86)
Build venv: C:\wapt-build-test
Lazarus 1.8.2
FPC 3.0.4 i386-win32
Lazarus: C:\lazarus
Inno Setup 5.6.0
ISCC: C:\git\binaries_cache\iscc\app\ISCC.exe
```

Historical OpenSSL 1.0.2u i386 was recovered for Windows requirements.

NSSM restored under:

``` text
waptservice\win32\nssm.exe
waptservice\win64\nssm.exe
```

`ujson==1.35` was built with VC9.

## 11. Windows Lazarus build chain â€” FINAL 7402

Nine Lazarus projects/modules are part of the final build:

``` text
wapt-get\waptget.lpi                         -> wapt-get.exe
wapt-get\waptguihelper.lpi                   -> waptguihelper.pyd
waptdeploy\waptdeploy.lpi                    -> waptdeploy.exe
wapttray\wapttray.lpi                        -> wapttray.exe
waptconsole\waptconsole.lpi                  -> waptconsole.exe
waptexit\waptexit.lpi                        -> waptexit.exe
waptself\waptself.lpi                        -> waptself.exe
waptmessage\waptmessage.lpi                  -> waptmessage.exe
waptsetup\waptsetuputil\waptsetuputil.lpi   -> waptsetuputil.dll
```

All nine final artifacts were rebuilt with:

``` text
FileVersion    1.8.2.7402
ProductVersion 1.8.2
```

Important build behavior:

- `lazbuild.py` must be invoked **one project at a time**.
- Passing multiple project paths in one invocation returned silently without rebuilding them.
- Use `C:\wapt-build-test\Scripts\python.exe .\lazbuild.py ...` because system `C:\Python27` lacks GitPython.
- `waptself` once triggered an intermittent Lazarus `EAccessViolation` / exit 217; rerunning it alone immediately succeeded with no source changes. Treat this as a transient lazbuild crash unless reproduced.
- `waptsetuputil` emits the known `WARNING: No compiler options`; final metadata/output are correct.

Direct bare `lazbuild.exe` is useful for diagnostics, but final version metadata must be produced through the historical wrapper mechanism.

## 12. VC90 CRT â€” RESOLVED

The VC90 manifest was corrected to match the recovered QFE DLLs:

``` text
9.0.30729.6161
```

Files:

``` text
msvcr90.dll
msvcp90.dll
msvcm90.dll
Microsoft.VC90.CRT.manifest
```

Committed in:

``` text
532404ef0 Fix VC90 CRT manifest for 9.0.30729.6161
```

Do not blindly replace every other historical manifest reference to `9.0.21022.8`; only change a manifest when its actual payload requires it.

## 13. Authenticode signing â€” FINAL 7402

Windows SDK SignTool:

``` text
C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe
```

Lab signing certificate:

``` text
Subject: CN=WAPT Lab Code Signing
Thumbprint: D8B8C49EEB204125D7609365D4CF604E8B7056AC
```

All nine final 7402 Lazarus artifacts were SHA-256 signed and verified successfully.

No timestamp was used for the lab validation.

The lab public certificate was trusted in LocalMachine Root + TrustedPublisher.

Never commit:

``` text
wapt-lab-codesign.pfx
wapt-lab-codesign.cer
```

The PFX/private key is a local lab artifact only.

The `waptconsole.exe` manifest still contains:

``` xml
<requestedExecutionLevel level="asInvoker" uiAccess="true"/>
```

Do not remove `uiAccess=true` merely to bypass signing. The unsigned launch failure on Windows 11 25H2 was resolved by signing.

For a production release, use the production code-signing certificate and preferably modern RFC3161 timestamping if compatible with the deployment requirements.

## 14. version-full â€” FINAL 7402

Generated with:

``` powershell
C:\wapt-build-test\Scripts\python.exe .\create_version_full.py
```

Validated:

``` text
version-full = 1.8.2.7402
git rev-list --count HEAD = 7402
HEAD = 895cb7597 Fix read-only SoGrid data loading
```

`version-full` is a generated/local artifact and is excluded locally; do not commit it unless release policy is deliberately changed.

## 15. Final WAPTSetup 7402

Historical setup build mechanism recovered from PowerShell history:

``` powershell
& "C:\git\binaries_cache\iscc\app\ISCC.exe" .\waptsetup\waptsetup.iss
```

`create_setup_simple.py` was not used; attempts failed because of historical environment assumptions (`git.repo` / `active_directory`).

Final installer:

``` text
C:\git\waptdev\waptsetup\waptsetup.exe
```

Metadata:

``` text
FileVersion    1.8.2.7402
ProductVersion 1.8.2.7402
ProductName    WAPTSetup
```

Final installer was signed with the lab Authenticode certificate and verified successfully.

Final SHA256:

``` text
ADD5FC3F6D81E394FD821EAA3AC7A3D3543DA9438C2AA474FAAE2B95DD41083C
```

This hash is an important release checkpoint.

## 16. WAPT package signing and waptupgrade numbering

Do not confuse three independent layers:

1.  Lazarus PE `FileVersion` / build metadata.
2.  `version-full`.
3.  WAPT package revision suffix after `-`.

`waptdevutils.py::build_waptupgrade_package()` reads the actual `wapt-get.exe` FileVersion, obtains the latest existing package revision, then increments it with `entry.inc_build()`.

Therefore the suffix is a **package release counter**, not the WAPT Git build number.

Final package:

``` text
deb10-waptupgrade 1.8.2.7402-49
```

Intermediate packages encountered during validation:

``` text
1.8.2.7401-46  historical/intermediate
1.8.2.7401-47  prior valid
1.8.2.7401-48  intermediate generated from installed 7401 console
1.8.2.7402-49  FINAL
```

Do not force the final suffix back to a lower number.

Final server file:

``` text
/var/www/wapt/deb10-waptupgrade_1.8.2.7402-49_all_1d9f09b71bd4a0f075b1bb1b7ba1cf2a.wapt
```

Recorded size:

``` text
27771279 bytes
```

MD5:

``` text
1d9f09b71bd4a0f075b1bb1b7ba1cf2a
```

Package metadata:

``` text
package: deb10-waptupgrade
version: 1.8.2.7402-49
architecture: all
section: base
priority: critical
target_os: windows
min_wapt_version: 1.7
signer: wapt-deb10-cert
signer_fingerprint: 13388c40c2ede5c347b4455e5fb394bf2292e8c39fcb68545a6ab273122e3c11
```

Physical package presence and repository metadata were validated. Do not reopen â€œpackage/index missingâ€ without contradictory evidence.

### WAPT signer vs Authenticode signer

These are separate trust systems:

- Authenticode signs Windows PE files.
- WAPT package signing uses the WAPT personal certificate/private key.
- Trusted WAPT package signer certificates live in the WAPT `ssl` trust root.
- `ssl\server` is HTTPS trust and is separate.

Current WAPT signer:

``` text
CN: wapt-deb10-cert
fingerprint: 13388c40c2ede5c347b4455e5fb394bf2292e8c39fcb68545a6ab273122e3c11
```

## 17. WAPTConsole functional validation â€” FINAL 7402

The final signed Community console:

- launches on Windows 11 25H2;
- authenticates to the Debian 10 lab server;
- displays hosts and package state;
- generates certificates/agents;
- creates and uploads waptupgrade packages;
- correctly displays available packages in Edit Machine after the SoGrid fix;
- can assign/save host dependencies;
- can trigger package installation through the normal console workflow.

Final console metadata:

``` text
FileVersion 1.8.2.7402
ProductVersion 1.8.2
Community Edition
```

The SoGrid â€œPaquets disponiblesâ€ defect is considered resolved for 7402.

## 18. Production-style Windows migration validation â€” PASS

### Test machine

VM105:

``` text
hostname: vm105.genevoix-signoret-vinci.fr.lan
UUID: 070A8580-54D0-4BD9-B3BA-49EE41C23D04
IP: 192.168.220.5
```

The VM was restored to an authentic production-connected WAPT 1.8.2.7393 snapshot before the final test.

Initial state:

``` text
Wrapper Win32.exe : wapt-get 1.8.2.7393
WAPTService: Running
repo_url=https://172.20.127.81/wapt
wapt_server=https://172.20.127.81
```

The stale VM105 server entry from earlier diagnostics was deleted from the lab WAPT console before the final test.

### Real deployment path tested

The agent was downloaded through the normal lab web interface:

``` text
waptagent.exe
FileVersion    1.8.2.7402
ProductVersion 1.8.2.7402
ProductName    WAPTAgent
```

It was installed directly **over the authentic 7393 installation**, with no manual pre-edit of `wapt-get.ini` and no manual stop/register/update preparation.

Result:

- installation completed;
- VM105 automatically returned to the WAPT console;
- `wapt-get.exe --version` became 1.8.2.7402;
- `WAPTService` was running;
- the generated agent replaced the old production endpoints with the lab endpoints.

Resulting configuration:

``` ini
[global]
repo_url=https://wapt-deb10.genevoix-signoret-vinci.fr.lan/wapt
send_usage_report=1
use_hostpackages=1
wapt_server=https://wapt-deb10.genevoix-signoret-vinci.fr.lan
use_kerberos=0
check_certificates_validity=1
verify_cert=0
use_repo_rules=0
max_gpo_script_wait=180
pre_shutdown_timeout=180
hiberboot_enabled=0

[wapt-templates]
repo_url=https://store.wapt.fr/wapt
verify_cert=1
```

### Host package / upgrade package validation

The final host package dependency was assigned through WAPTConsole.

Host package:

``` text
070A8580-54D0-4BD9-B3BA-49EE41C23D04
version 3
depends: deb10-waptupgrade
signer: wapt-deb10-cert
signer_fingerprint: 13388c40c2ede5c347b4455e5fb394bf2292e8c39fcb68545a6ab273122e3c11
```

WAPTConsole showed:

``` text
deb10-waptupgrade 1.8.2.7402-49
```

The normal console workflow installed it successfully. Final console state:

- VM105: `OK`;
- host package: installed/green;
- `deb10-waptupgrade 1.8.2.7402-49`: installed/green;
- audit task: Done;
- host reachable.

Final client checks:

``` text
wapt-get.exe --version -> 1.8.2.7402
wapt-get.exe list-upgrade -> no pending upgrades
```

During the final package workflow `WAPTService` was observed temporarily `Stopped`, then returned to:

``` text
Running
```

without manual intervention.

### Final verdict

**PASS â€” production-style Windows migration from authentic WAPT 1.8.2.7393 to the rebuilt WAPT 1.8.2.7402 is validated.**

Validated path:

``` text
authentic 7393 client
    -> portal-delivered waptagent.exe 7402
    -> install over existing WAPT
    -> automatic registration on new server
    -> host package assignment
    -> deb10-waptupgrade 1.8.2.7402-49
    -> final host OK / service Running / no pending upgrade
```

This is the preferred evidence for the real migration workflow.

## 19. UnknownIssuer diagnostic episode â€” NON-BLOCKING / CLOSED

During an earlier, more artificial VM105 test path, WAPT 7393 logged:

``` text
Error merging Packages from .../wapt-host into db:
EWaptCertificateUnknownIssuer:
None of certificates ("wapt-deb10-cert") are trusted.
```

Investigation established:

- the host package was signed by `wapt-deb10-cert`;
- its control fingerprint was the expected `13388c40...e3c11`;
- `WAPT/certificate.crt` contained the same self-signed certificate;
- the 7393 runtime's `authorized_certificates()` contained the same certificate/fingerprint;
- the error originates in the certificate-chain validation path when the relevant `SSLCABundle` does not accept the pinned certificate;
- `_update_db()` purges a repository before calling `repo.packages()`, but the exact rollback/disappearance chronology was not conclusively established.

The final restored-VM production-style migration succeeded without requiring a code change for this episode.

**Classification:** diagnostic artifact/non-blocking for the validated 7402 release path.

Do not reopen this investigation unless the same failure is reproduced in the real deployment workflow.

## 20. Known-good build/release commands and rules

Build metadata:

``` powershell
C:\wapt-build-test\Scripts\python.exe .\create_version_full.py
```

Final Lazarus builds:

- invoke `lazbuild.py` one project at a time;
- use the build venv Python;
- Community edition;
- let the Git commit count supply the natural build number.

Direct diagnostic console rebuild:

``` powershell
& "C:\lazarus\lazbuild.exe" `
  --primary-config-path="C:\Users\Maintenance\AppData\Local\lazarus" `
  -B `
  "C:\git\waptdev\waptconsole\waptconsole.lpi"
```

Final setup:

``` powershell
& "C:\git\binaries_cache\iscc\app\ISCC.exe" .\waptsetup\waptsetup.iss
```

Important rules:

- no `git add .`;
- restore Lazarus-generated `.lpi/.ico/hash` changes after build unless intentionally changed;
- do not commit lab signing keys/certificates;
- do not normalize legacy Pascal EOLs casually;
- do not remove `uiAccess=true`;
- do not change Synapse accidentally;
- do not reinstall/change Indy without a concrete blocker;
- do not treat all nine Lazarus outputs as EXEs: one is a PYD and one is a DLL;
- do not force package/build numbers;
- do not rebuild 7402 after adding a parent WAPT commit unless intentionally creating a new build number.

## 21. Debian 10 production-like server migration â€” VALIDATED

The Windows 7402 milestone remains frozen and validated. The production-like Debian 10 server migration milestone has now also been completed successfully.

### Final rebuilt Debian 10 server package

The first rebuilt Buster package was found to contain a temporary runtime-validation `conf/waptserver.ini`. Because `createdeb.py` copied the complete runtime into the package, `dpkg -i` could overwrite the persistent production configuration.

The defect was fixed in:

``` text
88170eee1738b8193966221cbcb03a18c9da4230
Prevent Debian upgrade from overwriting waptserver config
```

The Buster and Bookworm runtime builders now remove the temporary configuration after runtime tests. `waptserver/deb/createdeb.py` also refuses to build if `runtime_dir/conf/waptserver.ini` is present.

Final traceable Buster package:

``` text
tis-waptserver-1.8.2.7398-88170eee-debian-10-amd64.deb
Version: 1.8.2.7398-88170eee-debian-10-amd64
Architecture: amd64
SHA256: fb9406d37c50dfaaa3ee6aec417ac49f2b986730648bcfaf8c3c26be6266a823
Tag: server-buster-7398-validated
```

`dpkg-deb -c` confirmed that this package does **not** contain `/opt/wapt/conf/waptserver.ini`.

A clean production-like 7393 -> 7398 upgrade confirmed that the historical `waptserver.ini` is preserved bit-for-bit.

### Debian 10 migration script V1.0

Migration tool:

``` text
tools/waptserver-migrate-buster.sh
SCRIPT_VERSION="1.0"
BACKUP_FORMAT_VERSION="1"
SOURCE_BUILD="7393"
validated target build: 7398
```

Release commit:

``` text
cc96ac9f1011036358088dea5ed8906916df955b
Release Debian 10 WAPT migration script 1.0
```

Script SHA256:

``` text
e2a53b66a5348bc9789fcef6e6ce2704b03c36632a2ecb351f69507287f7ff55
```

Annotated release tag:

``` text
server-buster-migration-7393-7398-validated
```

Supported modes:

``` text
precheck
backup
check-backup
check-package
upgrade
```

The script performs source validation, verified PostgreSQL/configuration backups, exact target package validation, controlled `dpkg -i`, and post-upgrade checks. It intentionally does **not** run `postconf` and does not perform automatic rollback.

### Real production-clone validation

The final migration was tested on an isolated clone of a real historical production server rather than only on the synthetic Debian 10 lab.

Historical baseline:

``` text
Debian: 10 Buster
WAPT: 1.8.2.7393
Python: 2.7.16
DB marker: "1.8.2.1"

hostgroups: 3623
hostpackagesstatus: 25099
hosts: 675
hostsoftwares: 105247
packages: 1056
waptusers: 1
```

Final V1.0 migration result:

``` text
7393 -> 7398: PASS
RC: 0
Installed: 1.8.2.7398-88170eee-debian-10-amd64
waptserver.ini: preserved
DB marker: "1.8.2.1"
controlled DB counts: preserved
```

A format-1 migration backup was also created and independently validated:

``` text
/var/www/wapt-backups/migration-7393-7398-20260916-115658
```

Its manifest and SHA256 checks passed.

### Isolated clone topology and persistent safety

The real production clone is VM1900 and is now named:

``` text
scrab-clone
```

The true production server `scrab` must never be used for migration experiments.

The clone is attached only to the isolated Proxmox bridge:

``` text
hyp3 vmbr999:       10.99.99.1/24
scrab-clone eth0:   10.99.99.2/24
default route:      none
```

The historical production interface configuration initially returned after the first reboot because the lab address had only been applied dynamically. The original configuration was saved as:

``` text
/etc/network/interfaces.pre-isolation
```

Persistent `/etc/network/interfaces` is now:

``` text
auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet static
    address 10.99.99.2
    netmask 255.255.255.0
```

A subsequent reboot confirmed `10.99.99.2/24` with only the local `10.99.99.0/24` route and no default route.

The static and transient hostname were synchronized to `scrab-clone`.

**Never reconnect this clone to production `vmbr17`.**

### Post-reboot 7398 validation

After reboot, the migrated server remained functional:

``` text
waptserver.service: active/running
wapttasks.service:  active/running
nginx:              active
PostgreSQL WAPT DB: accessible
DB marker:          "1.8.2.1"
HTTPS:              HTTP/1.1 200 OK
```

Processes observed included both `wapttasks` and `waptserver`.

An earlier observation that `wapptasks.service` could not be found was transient and is superseded by the explicit post-reboot validation above.

### Agent 7402 / console 7402 against server 7398

VM106 was tested against the isolated clone without replacing its normal production-oriented `wapt-get.ini`. A separate temporary configuration was used through an SSH HTTPS tunnel:

``` text
VM106 localhost:8443
    -> hyp3
    -> 10.99.99.2:443
    -> nginx
    -> waptserver 7398
```

Validated operations:

``` text
HTTPS:                         PASS
agent 7402 repository update: PASS
agent 7402 registration:      PASS
agent 7402 update-status:     PASS
server DB receives VM106:     PASS
console 7402 loads VM106:     PASS
realtime reachability:        PASS
```

The historical repository package-signing certificate required explicit trust on the agent:

``` text
CN: 0790007d
SHA256:
1F:D8:56:F8:7E:68:B4:68:83:96:39:28:7A:A0:8E:44:13:86:9C:81:D7:8E:06:9C:D6:B1:91:7C:DD:45:67:34
```

The certificate embedded in the repository `Packages` archive is not automatically trusted by the agent. Explicitly restoring the relevant WAPT trust certificate is therefore part of the disaster-recovery requirements.

### Socket.IO and port 8088 â€” clarified

Server-side realtime communication uses:

``` text
agent / console
    -> HTTPS + Socket.IO on 443
    -> nginx /socket.io
    -> 127.0.0.1:8080
    -> waptserver
```

There is no required server-side WAPT port 8088.

Port `8088` is the local HTTP listener of the Windows WAPTService.

A temporary foreground WAPTService on VM106 using the isolated test configuration successfully established Socket.IO connectivity to `scrab-clone`; the console then showed VM106 as reachable.

The temporary second service produced a local SQLite `database is locked` message because the normal WAPTService remained active simultaneously. This was a deliberate test artifact, not a server defect. Only the temporary process was terminated afterward.

### Current validated chain

The following path is now validated:

``` text
historical Debian 10 / WAPT 7393
    -> verified migration backup
    -> controlled migration V1.0
    -> rebuilt Debian 10 / WAPT 7398
    -> historical DB/config preserved
    -> reboot survives
    -> agent 7402 interoperates
    -> console 7402 interoperates
    -> HTTPS / Socket.IO interoperates
```

This closes the production-like **in-place Debian 10 migration validation** milestone.

Remaining work before Debian 11 is now focused on proving autonomous reconstruction and disaster recovery:

1. install WAPT 7398 on a genuinely clean Debian 10 VM;
2. identify/document all OS and PostgreSQL prerequisites;
3. validate fresh server initialization;
4. restore historical 7393 DB/configuration/TLS/repository data onto the fresh server;
5. validate the restored server with console 7402 and agent 7402;
6. validate restoration from an evolved 7398 migration backup;
7. derive a reproducible fresh-install/disaster-recovery procedure;
8. only then begin Debian 10 -> Debian 11.

Build-environment reproducibility, SoGrid historical realignment and Python 3 modernization remain later work and must not alter the frozen Windows 7402 release.

## 22. Debian 10 fresh-install packaging preparation

Historical installation documentation confirms that a normal WAPT 1.8 Debian server installation used both `tis-waptserver` and `tis-waptsetup`. The fresh-install/DR validation must therefore include `tis-waptsetup`; validating `tis-waptserver` alone would not reproduce the historical installation model.

### Historical waptsetup naming

Repository history establishes why the server-side Windows installer is named `waptsetup-tis.exe`.

Commit `46619c63df691451d4945d0818026e2e86fad9cf` (`waptsetup.deb : correctifs`) explicitly changed the packaged executable from `waptsetup.exe` to `waptsetup-tis.exe` to avoid overwriting a potentially customized `waptsetup.exe`.

Therefore:

``` text
Windows build output:       waptsetup.exe
official server-side copy:  waptsetup-tis.exe
```

This is historical behavior and must be preserved.

### Reconstructed tis-waptsetup 7402

An isolated worktree was created at the immutable Windows tag:

``` text
v1.8.2.7402
895cb7597cf8d12ed149a3913dbfe197d39e5b62
git rev-count = 7402
```

A temporary local build branch pointing exactly at that commit was required because the historical builder uses GitPython `active_branch`.

The validated Windows 7402 artifacts were supplied to the builder:

``` text
waptsetup-tis.exe
SHA256 ADD5FC3F6D81E394FD821EAA3AC7A3D3543DA9438C2AA474FAAE2B95DD41083C

waptdeploy.exe
SHA256 C2C05314C9DBB8CF2118257C66D4CBD0FA6F75705D337B4131126552ED1A138D
```

The historical Debian builder successfully produced:

``` text
tis-waptsetup-windows-1.8.2.7402-895cb759.deb
Package:      tis-waptsetup
Version:      1.8.2.7402
Architecture: all
Depends:      nginx
SHA256: d51c8beaf1aedb6950d650e251afbf00f8baf85476851452d4502f8f51512b7e
```

Package extraction confirmed bit-for-bit that the embedded executables have exactly the validated 7402 hashes above. A preserved copy exists under `build/artifacts/debian10/` with the same package SHA256.

This package is a validated reconstruction artifact for fresh-install testing. It is not yet declared the final autonomous Debian release package.

### Server/setup version relationship

Historical `waptserver/deb/createdeb.py` and `waptsetup/deb/createdeb.py` both derive the fourth version component from `r.active_branch.commit.count()`.

The historical production installation also used matching build numbers:

``` text
tis-waptserver 1.8.2.7393-...
tis-waptsetup  1.8.2.7393
```

The current reconstructed artifacts intentionally come from two different development milestones:

``` text
Debian 10 validation server: 1.8.2.7398
Windows validated release:   1.8.2.7402
reconstructed setup package: 1.8.2.7402
```

Do not artificially rename 7398 to 7402.

Git history currently shows that the Windows 7402 lineage and Debian 10 lineage diverge from `4bbf306ad8342fc5637236c2f45aee9073ef0291`, with:

``` text
Windows 7402 side: 7 commits
Debian 10 side:    10 commits
Debian 10 HEAD:    cc96ac9f1011036358088dea5ed8906916df955b
Debian 10 rev-count: 7405
```

A future autonomous release should reunify the validated lineages and then build server/setup consistently from a common release state with a natural build number greater than 7405.

Do not perform that reunification until fresh-install and disaster-recovery validation is complete.

### Windows code-signing status

The validated Windows 7402 executables are currently signed using the temporary self-signed laboratory code-signing certificate.

They remain valid functional/build-reference artifacts, but this signature must not silently become the final distribution trust model.

Before freezing an autonomous production release, explicitly review the Windows code-signing strategy and revalidate any artifacts whose Authenticode signature or resulting SHA256 changes.


## 23. Exact next action

The immediate next milestone is:

``` text
FRESH DEBIAN 10 INSTALLATION + DISASTER-RECOVERY VALIDATION
```

Do **not** begin Debian 11 yet.

Create or use a genuinely clean, isolated Debian 10 VM with:

``` text
no inherited /opt/wapt
no inherited WAPT PostgreSQL database
no inherited WAPT configuration
no inherited WAPT repository
```

Then proceed in this order:

``` text
1. Inventory the pristine Debian 10 system.
2. Determine exact PostgreSQL/system prerequisites for WAPT 7398.
3. Install and initialize the preserved rebuilt WAPT 7398 artifacts.
4. Validate services, HTTPS, database and basic console/agent interoperability.
5. Restore the historical 7393 database, configuration, TLS material and repository.
6. Validate the restored server with console 7402 and agent 7402.
7. Validate restoration from a 7398-format migration backup.
8. Document the reproducible fresh-install + disaster-recovery procedure.
9. Only after PASS, begin Debian 10 -> Debian 11.
```

Keep all tests isolated. Never perform this validation on the true production server `scrab`.

### 23.1 Fresh Debian 10 installation validation - PASS (2026-09-17)

A genuinely pristine Debian 10 VM `wapt-deb10` was used. Before installation, no WAPT, PostgreSQL or nginx packages/services were present.

Validated local packages:

``` text
tis-waptserver 1.8.2.7398-88170eee-debian-10-amd64
SHA256 fb9406d37c50dfaaa3ee6aec417ac49f2b986730648bcfaf8c3c26be6266a823

tis-waptsetup 1.8.2.7402
SHA256 d51c8beaf1aedb6950d650e251afbf00f8baf85476851452d4502f8f51512b7e
```

APT successfully resolved and installed both packages together. Before `postconf.sh`, PostgreSQL 11/main existed on 5432, nginx was running, waptserver was installed but inactive, and `/opt/wapt/conf/waptserver.ini` did not exist. This confirms that corrected server package 7398 does not inject the temporary validation configuration. `waptsetup-tis.exe` and `waptdeploy.exe` were present under `/var/www/wapt/`.

Interactive `/opt/wapt/waptserver/scripts/postconf.sh` completed successfully with unauthenticated registration (historical compatibility mode), nginx configuration, FQDN `wapt-deb10.genevoix-signoret-vinci.fr.lan`, and startup of waptserver/wapttasks.

Validated after postconf:

``` text
PostgreSQL 11/main: online / 5432
WAPT database:       created
waptserver:          active/running
wapttasks:           active/running
nginx:               active/running
nginx:               80 / 443
waptserver:          127.0.0.1:8080
local HTTPS:         HTTP 200
VM106 HTTPS:         HTTP 200
```

### Fresh Windows client and agent publication

VM106's existing WAPT installation was removed. `waptsetup-tis.exe` was downloaded directly from the fresh server portal and installed with:

``` text
repository: https://wapt-deb10.genevoix-signoret-vinci.fr.lan/wapt
server:     https://wapt-deb10.genevoix-signoret-vinci.fr.lan/
```

VM106 successfully registered in the fresh database:

``` text
computer_fqdn: vm106.genevoix-signoret-vinci.fr.lan
UUID:          3154B5EF-2BAD-44A5-80FF-E31A6D7FCA1A
```

The original production 7393 setup and rebuilt 7402 setup were compared at the installation-options screen. Both expose the same choices and neither exposes a third Wizard choice. The Wizard shown in documentation is therefore not evidence of a regression in reconstructed 7402.

A new WAPT package-signing identity dedicated to this fresh environment was generated from WAPTConsole:

``` text
C:\private-wapt-deb10-fresh
basename: wapt-deb10-fresh
```

Its certificate was copied to the WAPT authorized package certificate store. The older `C:\private\wapt-deb10-cert.*` files dated 2026-09-14 were deliberately not reused.

Before agent generation the portal showed `Version WAPT Agent: N/A`. WAPTConsole 1.8.2.7402 then generated and published:

``` text
/var/www/wapt/waptagent.exe
FileVersion:    1.8.2.7402
ProductVersion: 1.8.2.7402
SHA256: 8b046b85f129ba3104aa2592c94a23fd56f6787913159112e02c1454718a1e92
```

After generation the portal showed `Version WAPT Agent: 1.8.2.7402`, exposed the Agent WAPT download, and advertised the matching SHA256.

Executable comparison confirmed that both the historical production 7393 `waptagent.exe` and freshly generated 7402 `waptagent.exe` are Authenticode `NotSigned`. Production 7393 setup/deploy are signed by TRANQUIL I.T. SYSTEMS; rebuilt 7402 setup/deploy are signed by the temporary `WAPT Lab Code Signing` certificate.

### Console/package deployment validation

WAPTConsole 1.8.2.7402 connected successfully to the fresh server and displayed VM106. An initial HTTP 401 was traced to a stale console configuration still pointing to `localhost:8443`; correcting the endpoint to the fresh-server FQDN resolved it.

The console assigned and successfully deployed:

``` text
deb10-waptupgrade 1.8.2.7402-45
```

to VM106. The task completed, the package was reported installed, and VM106 returned to status `OK`.

Validated chain:

``` text
pristine Debian 10
 -> tis-waptserver 7398 + tis-waptsetup 7402
 -> interactive postconf
 -> HTTPS / PostgreSQL / WAPT services
 -> setup downloaded from fresh portal
 -> fresh Windows installation + registration
 -> fresh package-signing identity
 -> waptagent.exe 7402 generation/publication
 -> console 7402
 -> successful package deployment to VM106
```

Result:

``` text
FRESH DEBIAN 10 INSTALLATION + WINDOWS CLIENT + PACKAGE DEPLOYMENT: PASS
```

### Remaining work before Debian 11

1. Trace why this fresh repository currently exposes `deb10-waptupgrade 1.8.2.7402-45`. The checkpoint already establishes that the suffix is a WAPT package revision counter, not the Git build number.
2. Restore historical 7393 DB/configuration/TLS/repository onto a clean reconstructed server and validate with console/agent 7402.
3. Validate restoration from an evolved 7398-format migration backup.
4. Document the reproducible fresh-install + disaster-recovery procedure.
5. Evaluate autonomous distribution without an external website: Git-synchronized installation versus a project-owned APT repository.
6. Only after disaster-recovery PASS, begin Debian 10 -> Debian 11.

## 24. Debian 10 historical DR validation — PASS (2026-09-18)

The fresh Debian 10 installation from section 23.1 was subsequently used
to validate a real disaster-recovery scenario from the historical WAPT
1.8.2.7393 production state.

The true production server `scrab` was never used for restoration tests.
Historical data came from the isolated `scrab-clone` and from the verified
migration backup:

``` text
/var/www/wapt-backups/migration-7393-7398-20260916-115658
```

Verified backup payload:

``` text
wapt-scrab.dump
SHA256 da015083db04e82be26b93be1cd2fe29718b011a15e4002706bd305d860f01d1

wapt-config-scrab.tar.gz
SHA256 64d15a21e400746d42daa0f3a003b1a47a999a0ff389a1e68e8a94a86b59c783
```

Historical database marker:

``` text
"1.8.2.1"
```

Historical controlled counts:

``` text
hosts:               675
hostgroups:          3623
hostpackagesstatus:  25099
hostsoftwares:       105247
packages:            1056
waptusers:           1
```

### PostgreSQL restore procedure — validated

The historical dump cannot simply be restored as the `wapt` role because
the dump needs sufficient privileges for objects such as the `hstore`
extension.

The validated procedure is:

1. create the target database owned by `wapt`;
2. remove the default `public` schema before restore because the dump
   recreates it;
3. run `pg_restore --no-owner` as the PostgreSQL superuser;
4. transfer ownership only for restored WAPT application tables and
   sequences to `wapt`;
5. restore the required schema ACL.

The schema ACL was an important finding. `waptserver` initially failed
with:

``` text
relation "serverattribs" does not exist
```

although `public.serverattribs` existed. The restored `public` schema did
not grant the WAPT role the required access.

Validated correction:

``` sql
GRANT USAGE, CREATE ON SCHEMA public TO wapt;
```

Do **not** use a global:

``` text
REASSIGN OWNED BY postgres TO wapt
```

because PostgreSQL owns system objects which must remain PostgreSQL-owned.

After the targeted ownership/ACL corrections, the historical WAPT
database was fully usable and its controlled counts matched the source.
Later changes in `hostpackagesstatus` are attributable to normal lab
client activity after restoration, not restore corruption.

### Historical configuration and TLS restore

The historical WAPT configuration, client CA, TLS material and nginx
configuration were restored from the verified backup.

The historical server certificate remains:

``` text
CN=scrab.genevoix-signoret-vinci.fr.lan
```

This is intentionally preserved during faithful DR. In the laboratory,
the restored server is addressed as
`wapt-deb10.genevoix-signoret-vinci.fr.lan`, so strict hostname
verification would not match. Do not alter production DNS or server
identity merely to make the laboratory hostname match.

The historical restored `waptserver.ini` retains its historical
permissions during faithful validation. Permission hardening is a later
modernization task, not part of the faithful DR proof.

### Historical repository restore — bit-for-bit validation

The migration backup does not contain the complete historical package
repository, so `/var/www/wapt` was transferred separately from the
isolated production clone.

Repository size was approximately 13 GiB.

Integrity was proven using sorted SHA256 manifests on both source and
destination:

``` text
source files:       847
destination files:  847

manifest SHA256:
8a67e8518ff96b47e40ac1c101c38113173183b67ed09ceafb91a0d86b725f67
```

Historical `/var/www/wapt/Packages` SHA256:

``` text
fbcb45ba5eca2ec6d2f183e951ffcdbe8ad9686d811bd4b1bc4f36f67ab364b1
```

The embedded historical package-signing certificate is:

``` text
CN: 0790007d
fingerprint:
1fd856f87e68b468839639287aa08e4413869c81d78e069cd6b1917cdd456734
```

The certificate embedded in the repository index does not automatically
establish client trust. Historical clients already trusting this
certificate can consume the restored repository normally.

### Package-signing key architecture — clarified

The historical `0790007d` package-signing private key is **not** part of
the WAPT server backup.

The server contains other private-key roles:

``` text
client-certificate CA private key
HTTPS/TLS server private key
```

These are distinct from the administrator's WAPT package-signing key.

Historical operational behavior was confirmed: the package-signing
certificate/private key belongs to the administrator/console environment
and must be backed up separately if signing continuity is required.

For this DR validation the historical administrator certificate/private
key was recovered from the administrative backup and loaded into
WAPTConsole 1.8.2.7402.

### waptupgrade revision baseline — corrected and validated

The historical source template contained:

``` text
waptupgrade/WAPT/control
version : 1.8.2.1-44
```

On a completely empty repository this caused a freshly generated package
to start at:

``` text
deb10-waptupgrade 1.8.2.7402-45
```

The source baseline was corrected to:

``` text
version : 1.8.2.1-0
```

Commit:

``` text
6591839b9 Reset waptupgrade package revision baseline
```

A real generation against an empty repository then produced:

``` text
deb10-waptupgrade 1.8.2.7402-1
```

This does not rewrite historical package history. When the restored
historical repository contains:

``` text
0790007d-waptupgrade 1.8.2.7393-16
```

the normal WAPT revision-continuity mechanism correctly generates:

``` text
0790007d-waptupgrade 1.8.2.7402-17
```

signed by:

``` text
0790007d
fingerprint:
1fd856f87e68b468839639287aa08e4413869c81d78e069cd6b1917cdd456734
```

The previously validated `deb10-waptupgrade 1.8.2.7402-49` remains a
valid historical reconstruction milestone and must not be rewritten.

### Repository restore rule for Setup/Deploy

A complete historical `/var/www/wapt` restore overwrote two files owned
by the installed target `tis-waptsetup` package:

``` text
/var/www/wapt/waptsetup-tis.exe
/var/www/wapt/waptdeploy.exe
```

This was proven by:

``` text
dpkg -V tis-waptsetup
```

which reported MD5 mismatches after the repository restore.

For the current validation, reinstalling the target
`tis-waptsetup 1.8.2.7402` restored the exact validated files:

``` text
waptsetup-tis.exe
SHA256 add5fc3f6d81e394fd821eaa3ac7a3d3543da9438c2aa474faae2b95dd41083c

waptdeploy.exe
SHA256 c2c05314c9dbb8cf2118257c66d4cbd0fa6f75705d337b4131126552ed1a138d
```

After correction:

``` text
dpkg -V tis-waptsetup
```

returned no output.

The **final DR procedure should not require this corrective reinstall**.
When restoring the historical repository, exclude:

``` text
wapt/waptsetup-tis.exe
wapt/waptdeploy.exe
```

so that the target files installed by `tis-waptsetup` remain untouched.

`waptagent.exe` is intentionally different: it should be regenerated
after restoration from the target/current WAPT console.

### Agent regeneration requirement

After restoring an older WAPT environment onto a newer reconstructed
target, the administrator must explicitly:

``` text
1. open the target/current WAPT console;
2. load/verify the intended package-signing certificate;
3. verify the authorized package-certificate bundle;
4. regenerate waptagent.exe and the waptupgrade package.
```

This requirement must be difficult to miss in the final DR tooling.
Decide later whether it is implemented as an end-of-restore message or
popup, a dedicated Markdown procedure, or both.

The DR-generated target agent used in this validation is:

``` text
FileVersion: 1.8.2.7402
SHA256:
857a2c3a06defc674ba6b1991bcc208449a6464b014e07c3d43801fed83dfab7
```

Inspection on a clean Windows system confirmed that generated agents
bundle certificates from the console's authorized certificates
directory. The package signer selected by the console and the authorized
certificate bundle embedded into the agent are separate concepts.

### Reboot validation — PASS

The faithfully restored server survived a complete reboot.

Validated after reboot:

``` text
waptserver:          active/running
wapttasks:           active/running
nginx:               active/running
postgresql:          active
PostgreSQL 11/main:  5432 online
DB marker:           "1.8.2.1"
HTTPS:               HTTP 200
repository files:    847
historical Packages: SHA256 preserved
```

An initially inconsistent `systemctl` observation for `wapttasks` was
transient. The unit existed, was enabled and its process had started at
boot. `daemon-reload` did not start the service.

### True historical client 7393 -> 7402 migration — PASS

VM104 was selected as a genuine laboratory client still running:

``` text
hostname: VM104
IP: 192.168.220.4
initial WAPT: 1.8.2.7393
```

Its WAPT trust store already contained the genuine historical package
certificate:

``` text
0790007d-20181217-150755.crt
```

Only VM104's internal WAPT endpoints were redirected from true production
to the reconstructed laboratory server. Production DNS and the true
production server were not modified.

Initial main WAPT configuration after redirection:

``` ini
[global]
repo_url=https://wapt-deb10.genevoix-signoret-vinci.fr.lan/wapt
wapt_server=https://wapt-deb10.genevoix-signoret-vinci.fr.lan
verify_cert=0

[wapt-templates]
repo_url=https://store.wapt.fr/wapt
verify_cert=1
```

The authentic 7393 client successfully read the restored repository:

``` text
Total packages: 167
Added:
  0790007d-waptupgrade (=1.8.2.7402-17)
Removed: none
Discarded packages count: 11
```

Both historical and new package versions were visible with the expected
historical signer/fingerprint.

#### Important dry-run finding

Running:

``` text
wapt-get -d install 0790007d-waptupgrade
```

correctly skipped `setup.install()` but nevertheless recorded
`0790007d-waptupgrade 1.8.2.7402-17` as `OK` in the local WAPT database.

The following normal install was therefore skipped although the actual
agent binary was still 7393.

**Do not use `-d / --dry-run` as a preflight for a real WAPT agent
upgrade.**

The supported `-f / --force` option was then used for the real test.

The package created the scheduled task `fullwaptupgrade` under
`NT AUTHORITY\SYSTEM` and reported:

``` text
Setting up upgrade from WAPT version 1.8.2.7393 to 1.8.2.7402.
```

After the scheduled task executed:

``` text
wapt-get.exe --version -> 1.8.2.7402
WAPTService -> Running / Automatic
fullwaptupgrade temporary task -> removed
console 7402 -> VM104 Reachable OK
0790007d-waptupgrade 1.8.2.7402-17 -> installed / OK
```

A final repository update from the upgraded client returned:

``` text
Total packages: 167
Added packages: none
Removed packages: none
Discarded packages count: 11
Pending operations: none
```

This proves the complete historical migration path:

``` text
authentic client 7393
    -> historical 0790007d trust
    -> reconstructed Debian 10 server 7398
    -> restored historical DB/config/TLS/repository
    -> console 7402 with historical package-signing key
    -> regenerated waptagent.exe 7402
    -> 0790007d-waptupgrade 1.8.2.7402-17
    -> scheduled self-upgrade
    -> client 7402
    -> WAPTService Running
    -> console Reachable OK
    -> repository update PASS
```

**PASS — fresh Debian 10 reconstruction + historical 7393 disaster
recovery + authentic client 7393 -> 7402 migration are validated
end-to-end.**

### Production-isolation conclusion

The restored production database contains historical production hosts,
but this does not redirect those hosts to the laboratory server. WAPT
agents initiate connections using their own configured repository/server
URLs.

The true production `scrab` address/DNS remains untouched. Only explicitly
reconfigured laboratory clients connect to `wapt-deb10`.

Never change production DNS or reconnect isolated clones as part of this
validation.

## 25. Consolidated autonomous release direction

The existing version numbers remain meaningful validation milestones:

``` text
7398 = Debian 10 reconstructed server/migration milestone
7402 = validated Windows client/console/setup milestone
```

Do not artificially rename the 7398 server to 7402.

After all remaining Debian 10 DR work is complete, the first deliberately
consolidated autonomous release is planned as:

``` text
1.8.3
```

Before freezing 1.8.3:

1. reunify the validated Windows and Debian source lineages;
2. build server/setup/client artifacts consistently from the common
   release state;
3. provide an autonomous installation/distribution mechanism which does
   not depend on obsolete external WAPT repositories;
4. explicitly review the final Windows Authenticode signing strategy;
5. keep Authenticode trust and WAPT package-signing trust distinct;
6. implement an explicit, idempotent database migration from marker
   `1.8.2.1` to at least `1.8.3.0`, even if no new tables or schema DDL
   are required;
7. validate the consolidated release before beginning Debian 11.

Do not alter the historical DR database marker during faithful 7393
validation. Its correct value remains:

``` text
1.8.2.1
```

## 26. Post-DR backup/restore tooling — current state (2026-09-18)

The historical 7393 disaster-recovery path and authentic Windows client
7393 -> 7402 migration are closed and validated. The strategy was revised:
do **not** immediately reset `wapt-deb10` merely to repeat a restore from an
evolved 7398 backup before the final DR mechanism exists.

The new order is:

``` text
historical 7393 DR validation
    -> reproducible autonomous DR backup/restore tooling
    -> end-to-end validation of that final mechanism with an evolved 7398 backup
    -> freeze Debian 10 DR
    -> consolidate 1.8.3
    -> Debian 11
```

Keep the current validated `wapt-deb10` state until the restore mechanism is
ready for its final validation.

### 26.1 DR backup/restore architecture

The existing migration script V1.0 remains frozen. Generic DR tooling is
separate:

``` text
tools/waptserver-backup.sh
future: tools/waptserver-restore.sh
future: higher-level administrative orchestrator if useful
```

Administrative scripts requiring root follow this convention:

``` text
already root -> continue unchanged
non-root + sudo -> re-exec through sudo preserving arguments
sudo unavailable/refused -> stop before modifications
```

Do not modify the frozen migration V1.0 merely to retrofit this convention.

The DR bundle format is versioned independently:

``` text
BACKUP_FORMAT_VERSION="1"
```

A backup with repository included contains conceptually:

``` text
wapt-dr-<hostname>-<timestamp>/
├── manifest.ini
├── SHA256SUMS
├── database/wapt.dump
├── config/waptserver.ini
├── config/nginx/wapt.conf
├── certificates/client-ca/
├── certificates/server-tls/
├── repository/wapt/
└── metadata/
    ├── system.txt
    ├── packages.txt
    ├── database.txt
    ├── repository.txt
    └── repository-manifest.sha256
```

Repository content is included by default by the `backup` mode and can be
omitted explicitly with `backup-no-repository`. Even when omitted, a per-file
SHA256 repository manifest is retained.

The administrator-visible backup consists of:

``` text
wapt-dr-<hostname>-<timestamp>.tar
wapt-dr-<hostname>-<timestamp>.tar.sha256
```

The SHA256 sidecar is deliberately retained because it permits immediate
integrity verification after transport or archival.

Backup-bundle security is independent of historical source permissions:

``` text
bundle directories: 0700 root:root
bundle files:       0600 root:root
final tar:          0600 root:root
SHA256 sidecar:     0600 root:root
```

The backup preserves historical repository content faithfully. Selective
modern target policy belongs to restore, not backup.

### 26.2 Restore policy already decided

The future restore tool must preserve target-version authority where
appropriate.

Historical repository restore must **not** overwrite the active files owned by
the target `tis-waptsetup` package:

``` text
/var/www/wapt/waptsetup-tis.exe
/var/www/wapt/waptdeploy.exe
```

Historical `waptagent.exe` may exist in the restored repository, but the final
administrative procedure must explicitly require regeneration of the agent
from the target/current console after trust has been reviewed.

Historical nginx configuration in the backup is reference material; restore
must not blindly overwrite the target nginx configuration.

`waptserver.ini` must also be restored selectively rather than blindly:
historical identity/policy values must be retained while target runtime/path
settings remain authoritative.

The historical package-signing private key remains an external
administrator/console asset and is not a WAPT server-backup payload.

The historical package prefix must be recorded and surfaced to the
administrator. Current historical value:

``` text
0790007d
```

Final operational repository permission policy planned for 1.8.3:

``` text
directories: 0750 wapt:www-data
files:       0640 wapt:www-data
```

Restore must reapply deliberate operational permissions rather than reproduce
the historical 0640/0644 mixture.

### 26.3 PostgreSQL restore contract

Source PostgreSQL version and port are **metadata**, not target configuration.

The restore tool must detect and use the target PostgreSQL runtime/cluster and
port. It must never restore the source PostgreSQL port or cluster configuration
blindly.

Example:

``` text
source: PostgreSQL 9.6 / port 5432
target: PostgreSQL 18 / port 5433

=> logical WAPT database restore targets PostgreSQL 18 / port 5433
```

Cross-major logical restoration still requires explicit compatibility
validation for extensions, data types and other PostgreSQL objects before it
can be guaranteed.

The validated historical database restoration rules remain:

``` text
create target DB owned by wapt
remove default public schema before pg_restore
pg_restore --no-owner as PostgreSQL superuser
targeted ownership correction for WAPT tables/sequences
GRANT USAGE, CREATE ON SCHEMA public TO wapt
```

Never globally `REASSIGN OWNED BY postgres TO wapt`.

### 26.4 `waptserver-backup.sh` development and validation

The standalone backup tool was developed incrementally on the isolated
`scrab-clone`.

Important milestones:

``` text
V0.1    precheck validated
V0.2    backup-no-repository introduced; PostgreSQL protected-directory issue found
V0.2.1  PostgreSQL dump fixed; real no-repository backup passed
V0.3    secure bundle normalization, repository SHA manifest, package-prefix detection
V0.3.1  neutral PostgreSQL working directory; clean no-repository backup passed
V0.4.x  final tar archive + repository-included mode + staging cleanup
V0.4.3  staging moved to backup filesystem + free-space preflight
```

A failed full-backup attempt while staging under `/tmp` filled the root
filesystem during repository copy. It was a controlled, source-safe failure
and exposed an architectural defect. The final design stages under the backup
destination filesystem, never inside the source repository.

For a full repository backup, free-space preflight requires:

``` text
2 * repository_size + 2 GiB safety margin
```

The factor 2 accounts for the repository staging copy plus the final tar.

### 26.5 Full V0.4.3 validation — PASS

The full backup was validated on `scrab-clone` against the real historical
repository.

Source characteristics:

``` text
server:              tis-waptserver 1.8.2.7398-88170eee-debian-10-amd64
database:            PostgreSQL 9.6 / port 5432
DB marker:           1.8.2.1
repository files:    847
repository bytes:    13246063582
historical prefix:   0790007d
```

Controlled database counts during the backup validation:

``` text
hostgroups:          3623
hostpackagesstatus:  25101
hosts:               675
hostsoftwares:       105247
packages:            1056
waptusers:           1
```

The `hostpackagesstatus` difference from the original 25099 baseline is
expected laboratory activity after restoration/migration, not backup
corruption.

Free-space preflight:

``` text
available bytes: 49810874368
required bytes:  28639610812
```

The repository copy was verified against its 847-entry SHA256 manifest before
archive creation.

Final validated archive:

``` text
/var/www/wapt-backups/wapt-dr-scrab-clone-20260918-123430.tar
```

SHA256:

``` text
a8809c603e377ec643cdfb44405179111a97bc4a410968132a638d4aedbe146b
```

Independent post-run validation confirmed:

``` text
archive exists and is readable
tar structure is valid
repository is included
temporary staging directory is absent
/var/www has 35 GiB free after completion
```

The repository SHA manifest generated independently by the backup tool again
matched the previously proven historical repository manifest:

``` text
8a67e8518ff96b47e40ac1c101c38113173183b67ed09ceafb91a0d86b725f67
```

### 26.6 Backup V1.0 — FROZEN

After full V0.4.3 validation, the script was promoted to:

``` text
tools/waptserver-backup.sh
SCRIPT_VERSION="1.0"
```

There was **no functional code change** between the validated V0.4.3 and V1.0;
only the script-version value changed.

V0.4.3 SHA256:

``` text
19bfa8ca8b277b4cd5e7bf8212e667c0ccc8f2155606ee1f29d4a5e8564d7490
```

V1.0 SHA256:

``` text
db8f75aa04fad3e7aa1419e446ddcf3fa19716565237e9ef3a7bde3a5fd8eede
```

`bash -n` passed.

Wapster commit:

``` text
226b2cc1 Add validated WAPT server DR backup tool
branch: build/debian10-buster
```

The authoritative checkpoint is **not** the untracked copy on Wapster.
The checkpoint reference remains the tracked file on VM106
`C:\git\waptdev\WAPT_CHECKPOINT.md`, updated from this document at major
milestones.

At the time of the V1.0 backup commit, Wapster working-tree status was:

``` text
?? WAPT_CHECKPOINT.md
```

The untracked Wapster checkpoint is an older duplicate and must not be
accidentally committed.

## 27. Exact next action

The historical 7393 DR path is closed and `waptserver-backup.sh` V1.0 is now
validated/frozen.

The immediate milestone is:

``` text
DESIGN AND IMPLEMENT THE REPRODUCIBLE WAPT SERVER RESTORE TOOL
```

Proceed in this order:

``` text
1. Commit/push the updated authoritative checkpoint separately from Wapster work.
2. Design `tools/waptserver-restore.sh` around BACKUP_FORMAT_VERSION=1.
3. Implement non-destructive validation/check mode first.
4. Implement safety backup + controlled restore sequencing.
5. Restore the logical WAPT DB into the detected target PostgreSQL runtime/port.
6. Restore historical identity/config selectively.
7. Restore repository while preserving target waptsetup-tis.exe/waptdeploy.exe.
8. Reapply deliberate target operational permissions.
9. Produce an explicit post-restore administrative report:
   - historical package signer/private key reminder;
   - authorized certificate review;
   - historical package-prefix verification;
   - regenerate waptagent.exe;
   - generate/publish the current <prefix>-waptupgrade package;
   - test at least one historical client.
10. Use an evolved 7398 backup as the end-to-end validation of the final DR mechanism.
11. Freeze the Debian 10 DR procedure only after that PASS.
12. Consolidate the validated lineages into release 1.8.3.
13. Only then begin Debian 11.
```

Do not reset the currently validated `wapt-deb10` merely to perform another
manual restore before the final restore mechanism exists.

Do not begin Debian 11 yet.

## 28. Resume protocol for a new ChatGPT thread

Attach this checkpoint and send:

``` text
Gipity, on reprend le projet WAPT à partir du checkpoint joint.
Considère WAPT_CHECKPOINT.md comme l'état technique faisant autorité.
Ne recommence pas les investigations déjà validées sauf si une contradiction apparaît.
On reprend à la section "Exact next action".
Réponses courtes, une étape à la fois.
```

If later work contradicts this file, update the checkpoint at the next major
milestone instead of silently rewriting history.

## 29. DR restore check tooling — validated milestone (2026-09-18)

Development of `tools/waptserver-restore.sh` began with a deliberately
non-destructive `--check` mode. No target WAPT database, configuration,
repository or services are modified by this mode.

The first validation exposed an important staging constraint: extracting a
repository-bearing DR bundle under `/tmp` can exhaust the root filesystem.
On `scrab-clone`, `/` had only about 6 GiB free while `/var/www` had about
35 GiB free. Restore-check staging was therefore moved to:

``` text
/var/www
```

The check now performs a free-space preflight before full extraction using:

``` text
required = archive size + 2 GiB safety margin
```

For the validated archive:

``` text
archive:
  /var/www/wapt-backups/wapt-dr-scrab-clone-20260918-123430.tar

archive size:
  13264957440 bytes

free space:
  36545908736 bytes

required:
  15412441088 bytes
```

The manifest parser was also simplified for compatibility with the Debian 10
AWK environment and the controlled format-1 INI syntax. The validated parser
reads values such as `format_version` directly from the `key = value` fields.

### 29.1 Full `--check` validation — PASS

The final check run on `scrab-clone` completed successfully:

``` text
WAPT Server DR restore check v0.1.5
CHECK PASSED
No target WAPT data was modified.
```

Validated controls:

``` text
archive present/non-empty:             PASS
archive SHA256 sidecar:                PASS
tar readability:                       PASS
archive path traversal protection:     PASS
single bundle root:                    PASS
manifest format precheck:              PASS
/var/www free-space preflight:         PASS
full bundle extraction:                PASS
required bundle files:                 PASS
BACKUP_FORMAT_VERSION=1:               PASS
mandatory identity files:              PASS
repository manifest SHA256:            PASS
repository per-file SHA256 (847):      PASS
bundle SHA256SUMS:                      PASS
PostgreSQL dump readable by pg_restore: PASS
```

Source metadata recovered correctly by the restore checker:

``` text
hostname:               scrab-clone
FQDN:                   scrab-clone.genevoix-signoret-vinci.fr.lan
Debian:                 10
WAPT server:            1.8.2.7398-88170eee-debian-10-amd64
DB marker:              "1.8.2.1"
source PostgreSQL:      9.6
source PostgreSQL port: 5432 (metadata only)
package prefix:         0790007d
repository included:    yes
repository files:       847
```

The exact script that passed this validation was frozen as a reference on
`scrab-clone`, transferred bit-for-bit through VM106 and then installed in
the Wapster development tree.

Validated script SHA256:

``` text
7fc62c4dd46e42bf9ea4daff7cf229e5d8732837bb3430d35d88cf91e09b5b88
```

Wapster commit:

``` text
faf4335b Add validated WAPT server DR restore check
branch: build/debian10-buster
```

The branch was pushed successfully:

``` text
cc96ac9f..faf4335b  build/debian10-buster -> build/debian10-buster
```

This push also publishes the previously committed backup V1.0 milestone:

``` text
226b2cc1 Add validated WAPT server DR backup tool
```

Wapster remains clean for tracked files; its old duplicate checkpoint remains
untracked and must not be committed:

``` text
?? WAPT_CHECKPOINT.md
```

VM106 remains the authoritative checkpoint working tree. Its intentional
`submodules/pltis_synapse` modification must remain untouched.

### 29.2 Restore development status

`tools/waptserver-restore.sh` is **not V1.0 yet**. Version 0.1.5 validates only
the non-destructive archive/check path. Do not promote it to V1.0 until the
actual controlled restore path has been implemented and validated end-to-end.

The next implementation phase must add the real restore sequencing while
preserving all policies already established in sections 24–27:

``` text
1. detect/validate target environment and target PostgreSQL runtime/port;
2. create a safety backup before modifications;
3. stop WAPT services in controlled order;
4. restore the logical WAPT database into the target PostgreSQL runtime;
5. apply targeted WAPT ownership and public-schema ACL;
6. selectively restore historical identity/policy configuration;
7. restore historical CA/TLS identity;
8. restore repository while preserving target:
     waptsetup-tis.exe
     waptdeploy.exe
9. reapply deliberate operational permissions;
10. restart and validate PostgreSQL/WAPT/nginx services and HTTPS;
11. emit an explicit post-restore administrative report covering:
     historical package-signing private key;
     authorized certificate review;
     package prefix;
     regeneration of waptagent.exe;
     generation/publication of current <prefix>-waptupgrade;
     validation with at least one historical client.
```

The first real destructive validation must remain isolated and must never
target the true production `scrab`.

## 30. Exact next action

The current immediate milestone is now:

``` text
IMPLEMENT THE CONTROLLED --restore PATH IN tools/waptserver-restore.sh
```

The archive/check layer is validated and committed. Continue development from
commit:

``` text
faf4335b
```

Do not redo the validated `--check` investigation unless a contradiction
appears. Develop the destructive restore path incrementally, preserve the
existing safety checks, and keep the script in the 0.x development series
until a complete real DR restore passes.

After the real restore mechanism is validated:

``` text
evolved 7398 backup
    -> validated restore tool
    -> complete reconstructed target validation
    -> historical client validation
    -> freeze restore V1.0
    -> freeze Debian 10 DR
    -> consolidate release 1.8.3
    -> Debian 11
```

Do not begin Debian 11 yet.
## 31. Restore target precheck — V0.2.1 functionally validated (2026-09-18)

Restore development continued from the committed V0.1.5 `--check` milestone.
The next objective was to validate the **target** before allowing any
destructive restore operation.

A V0.2 development interface added:

``` text
--check
--restore
```

At this stage `--restore` remained deliberately non-destructive and exited
after target validation.

### 31.1 PostgreSQL target-selection contract implemented

The first V0.2 candidate assumed exactly one online PostgreSQL cluster. This
was rejected before repository integration because it would be unnecessarily
strict on systems containing several legitimate clusters.

V0.2.1 instead:

``` text
1. enumerates online clusters reported by pg_lsclusters;
2. tests each cluster on its actual runtime port;
3. selects the unique online cluster containing an accessible database named wapt;
4. fails if zero or more than one matching WAPT database is found;
5. uses that detected cluster/version/port for all subsequent target operations.
```

This implements the previously agreed DR contract:

``` text
source PostgreSQL version/port = backup metadata only
target PostgreSQL runtime/port = detected from the restore target
```

It therefore does not blindly reuse a source port or PostgreSQL major version.

### 31.2 Real target used for validation

Target:

``` text
hostname:               wapt-deb10
Debian:                 10.13
tis-waptserver:         1.8.2.7398-88170eee-debian-10-amd64
tis-waptsetup:          1.8.2.7402
target PostgreSQL:      11.22 (Debian 11.22-0+deb10u2)
target cluster:         11/main
target port:            5432
target WAPT DB owner:   wapt
target DB marker:       "1.8.2.1"
waptserver.service:     active
```

The source DR archive was the validated Backup V1.0 artifact produced on
`scrab-clone`:

``` text
/tmp/wapt-dr-scrab-clone-20260918-123430.tar
/tmp/wapt-dr-scrab-clone-20260918-123430.tar.sha256
```

The archive was transferred through the isolated lab path:

``` text
scrab-clone -> hyp3 -> wapt-deb10
```

No production server was involved.

The archive occupied about 13 GiB. Before the check, the target filesystem
state was approximately:

``` text
filesystem: /dev/vda2
size:       62 GiB
used:       39 GiB
free:       20 GiB
usage:      67%

/tmp/wapt-dr-scrab-clone-20260918-123430.tar: ~13 GiB
/var/www/wapt:                                      ~13 GiB
```

There were no significant stale DR staging trees to remove. Only small
previous-test artifacts existed:

``` text
/var/www/wapt-fresh-before-dr: ~80 MiB
/root/pre-dr-fresh:            ~104 KiB
```

### 31.3 V0.2.1 `--restore` precheck — PASS

The non-destructive target-precheck run completed successfully.

Important output:

``` text
Source PostgreSQL:      9.6
Source PostgreSQL port: 5432 (metadata only)

Target Debian:          10
Target WAPT server:     1.8.2.7398-88170eee-debian-10-amd64
Target WAPT setup:      1.8.2.7402
Target PostgreSQL:      11.22 (Debian 11.22-0+deb10u2)
Target PG cluster:      11/main
Target PostgreSQL port: 5432
Target DB owner:        wapt
Target DB marker:       "1.8.2.1"

[ OK ] Restore target precheck passed

RESTORE PRECHECK PASSED
No target WAPT data was modified.
```

This experimentally proves that the restore checker distinguishes source
PostgreSQL metadata from the actual target runtime.

The run also repeated the already-established format-1 archive checks,
including repository and bundle SHA256 validation. These integrity checks are
retained for safety, but avoid asking the administrator to perform additional
manual SHA256 passes over the 13 GiB archive unless they are actually needed.
The scripted integrity controls are sufficient during normal restore workflow.

The large extraction again used `/var/www`, never `/tmp`.

After completion:

``` text
df -h / -> about 20 GiB free again
find /var/www -maxdepth 1 -type d -name '.wapt-dr-restore-*' -> no result
```

Therefore cleanup of the temporary extraction tree is also validated.

The initial V0.2.1 test binary still displayed `v0.2` because the internal
version string had not been incremented when the PostgreSQL-selection logic
was changed. This was corrected afterward to:

``` text
SCRIPT_VERSION="0.2.1"
```

No second 13 GiB validation run is required merely for that version-string
correction.

On Wapster, the corrected V0.2.1 was copied into:

``` text
tools/waptserver-restore.sh
```

Current tracked/untracked state at that point:

``` text
 M tools/waptserver-restore.sh
?? WAPT_CHECKPOINT.md
```

The untracked Wapster `WAPT_CHECKPOINT.md` remains the known old duplicate and
must not be committed. VM106 remains the authoritative checkpoint working
tree.

V0.2.1 has **not** been committed as a separate milestone. The last committed
restore baseline remains:

``` text
faf4335b Add validated WAPT server DR restore check
```

## 32. Lightweight target safety-backup design and V0.3 candidate

Before implementing destructive restore operations, the target safety-backup
policy was clarified.

### 32.1 Safety-backup scope

A fresh reconstruction target is expected to have little or no historical
package payload in `/var/www/wapt`; the important package-owned artifacts are
primarily:

``` text
/var/www/wapt/waptsetup-tis.exe
/var/www/wapt/waptdeploy.exe
```

The current `wapt-deb10` contains about 13 GiB only because it has already
served as the manual historical DR validation target.

Duplicating the entire current repository before every restore would therefore
consume large amounts of disk space without matching the normal clean-target
scenario.

The agreed safety-backup contract is:

``` text
SAFETY BACKUP = mutable critical target state, WITHOUT repository package payload
DR ARCHIVE     = complete restoration source, optionally including repository
```

The safety backup should contain:

``` text
- logical PostgreSQL dump of the current target WAPT database;
- /opt/wapt/conf;
- target WAPT server TLS directory;
- target nginx WAPT configuration as reference;
- target Debian/WAPT/PostgreSQL/cluster/port/DB-marker metadata;
- lightweight repository inventory;
- target waptsetup-tis.exe if present;
- target waptdeploy.exe if present.
```

It deliberately does **not** copy the package/repository payload.

This safety archive is intended to protect the target's critical mutable state
before destructive restore work. By design, it is **not** a bit-for-bit
rollback copy of the previous repository payload, and the script/report must
not imply otherwise.

This resolves the disk-space problem on the current 62 GiB `wapt-deb10`
without weakening the main DR archive.

### 32.2 Repository restore authority remains unchanged

During the later real repository restore, historical content from the DR
archive must still preserve the target package-owned files:

``` text
waptsetup-tis.exe
waptdeploy.exe
```

Those files remain authoritative from the target `tis-waptsetup` package,
currently 1.8.2.7402.

Historical `waptagent.exe` may be restored temporarily with repository
content, but the final administrative procedure must require regeneration
from the current console after authorized-certificate review.

### 32.3 V0.3 candidate prepared — NOT YET EXECUTION-VALIDATED

A complete V0.3 candidate was generated from the validated V0.2.1 development
state.

Candidate script SHA256:

``` text
9d89b2deee2b499be4d43f429be5e6276aae9af61811abc781867f41fe23f6ca
```

Wapster validation performed:

``` text
sha256sum: expected value matched
bash -n:   PASS
diff V0.2.1 -> V0.3: reviewed
```

V0.3 adds:

``` text
- SCRIPT_VERSION="0.3";
- automatic sudo re-exec for --restore when not already root;
- creation of /var/www/wapt-backups if needed;
- secure lightweight target safety-backup staging;
- target PostgreSQL custom-format dump;
- capture of /opt/wapt/conf;
- capture of /opt/wapt/waptserver/ssl;
- capture of nginx WAPT configuration when present;
- copy of waptsetup-tis.exe and waptdeploy.exe when present;
- target metadata;
- repository inventory only, not repository payload;
- 0700 safety-backup directories and 0600 files/archive;
- structural tar validation;
- pg_restore readability validation of the DB dump inside the safety archive;
- cleanup of safety-backup staging;
- deliberate barrier after successful safety backup.
```

The intended V0.3 terminal barrier is:

``` text
SAFETY BACKUP PASSED
Destructive restore operations are not implemented yet in v0.3.
Target database, configuration and repository were NOT replaced.
```

V0.3 does **not** yet:

``` text
- stop WAPT/nginx services;
- drop or replace the target database;
- restore the source database;
- merge waptserver.ini;
- restore historical CA/TLS identity;
- restore repository content;
- change operational repository permissions;
- perform final service/HTTPS/client validation.
```

Therefore V0.3 is currently:

``` text
SYNTAX VALIDATED + DIFF REVIEWED
NOT YET EXECUTION-VALIDATED
NOT COMMITTED
```

Do not describe it as a validated restore milestone until the lightweight
safety-backup run has actually passed on the isolated target.

## 33. Exact next action — weekend resume point

The project is deliberately stopped at a safe boundary. No destructive restore
operation is in progress.

The immediate next milestone is:

``` text
EXECUTE AND VALIDATE V0.3 LIGHTWEIGHT TARGET SAFETY BACKUP
```

Resume in this order:

``` text
1. Keep the validated V0.2.1 state as the functional target-precheck reference.
2. Transfer/use the already reviewed V0.3 candidate on isolated wapt-deb10.
3. Run V0.3 --restore against the validated format-1 DR archive.
4. Confirm:
     - target precheck still passes;
     - safety DB dump is valid;
     - critical target config/identity is captured;
     - package-owned setup/deploy artifacts are captured when present;
     - repository payload is NOT duplicated;
     - safety archive is structurally valid;
     - staging is cleaned;
     - no target DB/config/repository has been replaced.
5. Inspect safety archive size and free-space recovery.
6. If PASS, preserve the exact V0.3 script and record the validation milestone.
7. Only then implement the next destructive-development phase:
     - controlled service stop;
     - logical DB replacement into detected target PostgreSQL runtime;
     - targeted ownership/schema ACL repair;
     - deliberate barrier and validation before config/repository restoration.
8. Continue incrementally through selective config/identity restore,
   repository restore preserving waptsetup-tis.exe/waptdeploy.exe,
   operational permissions, restart and final administrative report.
9. After a complete real DR restore passes, validate with an evolved 7398
   backup and at least one historical client.
10. Freeze restore V1.0 and Debian 10 DR only after those PASS results.
11. Consolidate the first autonomous release as 1.8.3.
12. Only then begin Debian 11.
```

Important weekend/restart rules:

``` text
- true production scrab remains untouched;
- scrab-clone remains isolated on vmbr999 with no default route;
- large restore staging belongs under /var/www, never /tmp;
- source PostgreSQL version/port are metadata only;
- detect the target cluster containing database wapt;
- do not duplicate the repository in the lightweight safety backup;
- preserve target waptsetup-tis.exe and waptdeploy.exe during repository restore;
- do not commit Wapster's untracked duplicate WAPT_CHECKPOINT.md;
- VM106 C:\git\waptdev\WAPT_CHECKPOINT.md is the authoritative checkpoint;
- do not begin Debian 11.
```

The resume protocol remains:

``` text
Gipity, on reprend le projet WAPT à partir du checkpoint joint.
Considère WAPT_CHECKPOINT.md comme l'état technique faisant autorité.
Ne recommence pas les investigations déjà validées sauf si une contradiction apparaît.
On reprend à la section "Exact next action".
Réponses courtes, une étape à la fois.
```
## 34. Restore target safety backup — V0.3.1 validated and committed (2026-09-21)

Development resumed from the V0.3 candidate described in section 32.

The first real V0.3 `--restore` run completed all archive and target prechecks,
then created the lightweight target safety backup, but failed only during its
final embedded-dump readability check:

``` text
[FAIL] Database dump inside target safety-backup archive is not readable
```

The safety archive itself was valid. The defect was the validation command:

``` text
tar -xOf .../wapt.dump | pg_restore -l -
```

In this context `pg_restore -l -` treated `-` as an input filename rather than
reading the archive from standard input. Independent checks proved both the
staged dump and the dump streamed from the generated tar were readable.

V0.3.1 changed only:

``` text
SCRIPT_VERSION="0.3" -> "0.3.1"
pg_restore -l -      -> pg_restore -l
```

Validated V0.3.1 SHA256:

``` text
40c927865dd0a6e6062a423a24b53c7dbe0d95fd7158370a62b8df5ce8335c5a
```

The successful V0.3.1 run on isolated `wapt-deb10` produced:

``` text
/var/www/wapt-backups/wapt-target-safety-wapt-deb10-20260921-092815.tar
```

Validation result:

``` text
RESTORE PRECHECK PASSED
Target safety backup created and structurally validated
SAFETY BACKUP PASSED
```

Post-run checks confirmed:

``` text
safety archive size: about 45 MiB
archive mode:        0600 root:root
staging residue:     none
free space /var/www: about 20 GiB
waptserver:          active
postgresql:          active
nginx:               active
```

The lightweight archive contains critical mutable target state but deliberately
does not contain repository package payload. It includes the logical WAPT DB
dump, WAPT configuration, server TLS material, nginx WAPT configuration when
present, target metadata, repository inventory and target
`waptsetup-tis.exe`/`waptdeploy.exe` when present.

The exact validated restore script was committed and pushed on
`build/debian10-buster`:

``` text
c7f98b36 Add validated target safety backup to WAPT DR restore
```

The previous V0.3 failed-test archive was retained as diagnostic evidence; its
temporary staging directory was removed.

## 35. Controlled logical database restore — V0.4.4 validated and committed (2026-09-21)

The next restore milestone deliberately implemented only the destructive
database phase, retaining a hard stop before configuration, certificates,
nginx and repository restoration.

The intended sequence was:

``` text
validated archive/target prechecks
-> validated lightweight target safety backup
-> stop WAPT application services
-> keep PostgreSQL active
-> replace logical WAPT database on detected target PostgreSQL cluster/port
-> targeted ownership/schema ACL repair
-> validate DB marker and essential table counts
-> STOP BARRIER before config/identity/repository restore
```

Target PostgreSQL remained authoritative:

``` text
target PostgreSQL: 11/main
target port:       5432
source PostgreSQL: 9.6 / 5432 (metadata only)
```

### 35.1 V0.4/V0.4.1 PostgreSQL 11 compatibility finding

Before destructive execution, the sequence-owner validation was checked on the
real PostgreSQL 11 target. PostgreSQL 11 does not expose
`sequence_owner` through `information_schema.sequences`.

The validation was corrected to use:

``` text
pg_class
pg_namespace
pg_get_userbyid(c.relowner)
```

The corrected query was tested directly on PostgreSQL 11 and returned zero
non-WAPT-owned public sequences.

V0.4.1 SHA256:

``` text
4dc1bcebf66e406ace9812f915b54762818e9e267668cb10af841007248e386b
```

### 35.2 First destructive run — controlled failure and root cause

V0.4.1 successfully:

``` text
created/validated a new target safety backup
stopped WAPT application services
kept PostgreSQL active
dropped/recreated database wapt
removed the default public schema
```

It then failed before importing any dump data:

``` text
pg_restore: could not open input file .../database/wapt.dump: Permission denied
[FAIL] Database restore failed
```

The extracted DR staging tree is intentionally private to root. The
`postgres` user therefore could not traverse the root-owned staging path to
open the dump directly.

This did **not** justify weakening staging permissions. The design was fixed
instead so root reads the protected dump and streams it to `pg_restore`
running as `postgres`:

``` text
root-readable dump -> stdin -> pg_restore as postgres
```

V0.4.2 implemented this change.

After the V0.4.1 interruption:

``` text
waptserver: inactive
wapttasks:  failed/stopped
postgresql: active
nginx:      active
database wapt: exists, 0 public tables
```

The pre-failure safety backup was preserved:

``` text
/var/www/wapt-backups/wapt-target-safety-wapt-deb10-20260921-094608.tar
```

### 35.3 Controlled interrupted-restore recovery

V0.4.2 initially could not resume because the normal target precheck required
`waptserver` to be active.

V0.4.3 added a deliberately narrow recovery rule:

``` text
if waptserver is inactive:
    detect the real target PostgreSQL WAPT database;
    require exactly 0 public tables;
    only then accept the state as an interrupted database restore.
```

It does not broadly permit restoring over an arbitrary inactive WAPT server.

The first V0.4.3 resume correctly recognized:

``` text
waptserver inactive
target database has 0 public tables
interrupted restore state accepted
```

It then stopped during the normal target DB-marker check because an empty
interrupted database has no `serverattribs` table.

V0.4.4 therefore skips the **target pre-restore marker** only after the exact
empty interrupted-restore state above has already been accepted. The source
marker remains validated from the DR archive, and the restored marker is still
required and validated after `pg_restore`.

Validated V0.4.4 SHA256:

``` text
7cfbefc52e5dafaf39a119a30c81ca485af54fd2298039a24cbe2556f27fc842
```

### 35.4 V0.4.4 destructive DB restore — PASS

The V0.4.4 resume completed successfully.

A fresh lightweight target safety backup was created and validated:

``` text
/var/www/wapt-backups/wapt-target-safety-wapt-deb10-20260921-101625.tar
```

The logical database was restored into:

``` text
PostgreSQL cluster: 11/main
port:               5432
database owner:     wapt
```

The restore used `pg_restore --no-owner` as PostgreSQL superuser, followed by
targeted WAPT ownership corrections and:

``` sql
GRANT USAGE, CREATE ON SCHEMA public TO wapt;
```

No global `REASSIGN OWNED BY postgres TO wapt` was used.

Post-restore validation:

``` text
DB marker:           "1.8.2.1"

hostgroups:          3623
hostpackagesstatus:  25101
hosts:               675
hostsoftwares:       105247
packages:            1056
waptusers:           1
```

The script reported:

``` text
[ OK ] Logical database restore completed
[ OK ] Restored database ownership, schema ACL, marker and essential tables validated

DATABASE RESTORE PASSED
```

The result matches the evolved 7398 backup baseline established by Backup
V1.0.

At the intentional stop barrier:

``` text
waptserver/wapttasks remain stopped
PostgreSQL remains active
target configuration not yet restored
target certificates/TLS not yet restored
target nginx configuration not replaced
target repository not yet restored
```

Temporary restore staging cleanup was also validated:

``` text
find /var/www -maxdepth 1 -name '.wapt-dr-restore-*'
-> no output
```

The protected root-only staging permissions were **not** weakened. The
permission issue was solved by streaming the DB dump rather than granting
`postgres` access to the staging tree.

The exact validated script was committed and pushed:

``` text
cbc158fc Add validated WAPT database restore phase
branch: build/debian10-buster
```

Current Wapster tracked state after push is clean. Its old duplicate checkpoint
remains intentionally untracked:

``` text
?? WAPT_CHECKPOINT.md
```

Do not commit that Wapster duplicate. VM106 remains the authoritative
checkpoint working tree.

## 36. Exact next action — post-V0.4.4 database barrier

The current `wapt-deb10` restore is intentionally paused after successful
database replacement.

Current known state:

``` text
database:            restored and validated from evolved 7398 DR archive
DB marker:           "1.8.2.1"
PostgreSQL 11/main:  active on 5432
waptserver:          stopped
wapttasks:           stopped/failed state from controlled stop
nginx:               active
config/identity:     not yet restored by the automated restore tool
repository:          not yet restored by the automated restore tool
```

Do **not** restart WAPT services yet. The database is historical/restored while
the remaining target configuration/identity/repository layers have not yet
been applied by the automated restore sequence.

The immediate implementation milestone is:

``` text
SELECTIVE CONFIGURATION / IDENTITY / REPOSITORY RESTORE
```

Proceed incrementally:

``` text
1. Preserve V0.4.4 / commit cbc158fc as the validated DB-restore rollback point.
2. Implement selective waptserver.ini restoration:
     - preserve target runtime/path/technical authority;
     - restore historical identity/policy values deliberately.
3. Restore historical client CA and server TLS identity deliberately.
4. Keep target nginx configuration authoritative; historical nginx config is
   reference material only.
5. Restore repository content from the DR archive while preserving target:
     waptsetup-tis.exe
     waptdeploy.exe
6. Reapply deliberate operational permissions:
     repository directories 0750 wapt:www-data
     repository files       0640 wapt:www-data
     /opt/wapt/conf         0750 wapt:root
     waptserver.ini         0640
     client CA certificate  0644
     client CA private key  0640
     server TLS directory   0750 root:root
     server TLS certificate 0644
     server TLS private key 0600
7. Validate restored configuration/identity/repository before restarting WAPT.
8. Restart services in controlled order and validate PostgreSQL, WAPT, nginx,
   HTTPS and repository access.
9. Emit the final administrative report/reminders:
     - historical package-signing private key remains external;
     - review authorized package certificates;
     - verify historical package prefix (`0790007d`);
     - regenerate `waptagent.exe` from the current console;
     - generate/publish the current `<prefix>-waptupgrade`;
     - validate at least one historical client.
10. Complete an end-to-end evolved-7398 restore validation.
11. Only after the complete restore passes, promote restore tooling toward V1.0
    and freeze Debian 10 DR.
12. Then add/finalize the post-DR modernization roadmap and consolidate the
    first autonomous release as 1.8.3.
13. Do not begin Debian 11 yet.
```

Important continuity rules remain unchanged:

``` text
true production scrab remains untouched
scrab-clone remains isolated on vmbr999 with no default route
large restore staging belongs under /var/www, never /tmp
source PostgreSQL version/port are metadata only
target PostgreSQL cluster/port are detected dynamically
safety backup does not duplicate repository payload
target waptsetup-tis.exe and waptdeploy.exe remain authoritative
Wapster's untracked WAPT_CHECKPOINT.md is not authoritative
VM106 C:\git\waptdev\WAPT_CHECKPOINT.md remains authoritative
```
## 37. Selective configuration / identity restore — V0.5.1 validated (2026-09-21)

Restore development continued from the validated V0.4.4 database barrier.

V0.5.1 added resume-aware selective restoration of WAPT configuration and
identity. Its validated SHA256 is:

``` text
0c30658dc7ec00725158c4ed5be3b69517fdfa93648158fa4e8c5e9cf689af70
```

The restore state machine now distinguishes:

``` text
normal
interrupted-empty
interrupted-partial
post-database
```

A `post-database` state is accepted only when the restored database matches the
source logical signature: DB marker, database/schema ownership and ACL, zero
non-WAPT-owned application tables/sequences, and exact controlled source table
counts. In that state the destructive database replacement is skipped.

On the already restored `wapt-deb10`, V0.5.1 correctly detected:

``` text
post-database
DATABASE RESTORE SKIPPED
```

and created a fresh lightweight safety backup:

``` text
/var/www/wapt-backups/wapt-target-safety-wapt-deb10-20260921-110332.tar
```

### 37.1 Selective `waptserver.ini` authority

Target runtime/technical values remain authoritative, including:

``` text
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

Historical identity/policy values are restored deliberately, including:

``` text
server_uuid
secret_key
wapt_password
allow_unauthenticated_connect
allow_unauthenticated_registration
clients_signing_certificate
clients_signing_key
```

Validated restored identity/policy included:

``` text
server_uuid = 39904430-d99a-11e7-ae3b-0208840a277e
allow_unauthenticated_connect = False
allow_unauthenticated_registration = True
clients_signing_key = /opt/wapt/conf/ca-scrab.genevoix-signoret-vinci.fr.lan.pem
clients_signing_certificate = /opt/wapt/conf/ca-scrab.genevoix-signoret-vinci.fr.lan.crt
```

Historical client-CA material and historical server TLS material were restored.
The target nginx configuration remained authoritative and was not replaced.

Validated permission policy:

``` text
/opt/wapt/conf:                 0750 wapt:root
waptserver.ini:                 0640
client CA certificate:          0644
client CA private key:          0640
server TLS directory:           0750 root:root
server TLS certificate:         0644
server TLS private key:         0600
```

The historical server TLS certificate is self-signed and has:

``` text
CN = scrab.genevoix-signoret-vinci.fr.lan
notBefore = Dec 5 08:56:54 2017 GMT
notAfter  = Dec 3 08:56:54 2027 GMT
```

Preserve this certificate for faithful DR. Plan and validate renewal/replacement
for the same WAPT service FQDN before **2027-12-03**. Do not confuse this HTTPS
server certificate with the WAPT client-signing CA or the external package
signing certificate/private key.

At this stage `waptserver` and `wapttasks` intentionally remained stopped.

## 38. Historical repository restore — V0.6.2 validated and committed (2026-09-21)

Repository restoration was implemented while preserving the target-version
files owned by `tis-waptsetup`:

``` text
/var/www/wapt/waptsetup-tis.exe
/var/www/wapt/waptdeploy.exe
```

A V0.6.1 run restored the repository correctly but its final manifest
validation reported exactly two mismatches because the manifest filter did not
normalize `./` paths correctly. Diagnostics proved that the only mismatches
were the two intentionally preserved target executables; the 13 GiB historical
repository itself was not corrupted.

V0.6.2 corrected the manifest filtering and added a resume check that avoids
copying the 13 GiB payload again when the target already matches the source
except for those two preserved files.

Validated V0.6.2 SHA256:

``` text
63c67f60a7b232e1f77c6b01781503f3b4098ec9eb81896cea55598d1505b610
```

Validated result:

``` text
repository files: 847
Packages SHA256:
fbcb45ba5eca2ec6d2f183e951ffcdbe8ad9686d811bd4b1bc4f36f67ab364b1

preserved waptsetup-tis.exe SHA256:
add5fc3f6d81e394fd821eaa3ac7a3d3543da9438c2aa474faae2b95dd41083c

preserved waptdeploy.exe SHA256:
c2c05314c9dbb8cf2118257c66d4cbd0fa6f75705d337b4131126552ed1a138d
```

Operational repository permissions were reapplied as:

``` text
directories: 0750 wapt:www-data
files:       0640 wapt:www-data
```

The exact validated repository phase was committed and pushed on
`build/debian10-buster`:

``` text
74bbf2ae Add validated WAPT repository restore phase
```

At this barrier:

``` text
database:          restored/validated
config/identity:   restored/validated
repository:        restored/validated
PostgreSQL/nginx:  active
waptserver:        intentionally stopped
wapttasks:         intentionally stopped
```

## 39. Service / FQDN / TLS validation — V0.7.2 PASS (2026-09-21)

The final automated restore phase added controlled service startup and explicit
WAPT service-identity validation.

An important architectural distinction was proven:

``` text
source OS FQDN:    scrab-clone.genevoix-signoret-vinci.fr.lan
WAPT service FQDN: scrab.genevoix-signoret-vinci.fr.lan
target OS FQDN:    wapt-deb10.genevoix-signoret-vinci.fr.lan
```

The source OS hostname is **not** the WAPT service identity. For this historical
backup format the WAPT service FQDN is derived from the restored TLS
certificate CN.

V0.7.1 first validated TLS key/certificate matching, certificate validity,
nginx configuration, and service startup. Its first local HTTPS test returned
HTTP 502 immediately after systemd reported `waptserver` active. Diagnostics
showed:

``` text
nginx proxy target: 127.0.0.1:8080
waptserver listener: 127.0.0.1:8080
```

and the same HTTPS request returned HTTP 200 shortly afterward. This proved a
startup-readiness race rather than a broken proxy/backend configuration.

V0.7.2 replaced the one-shot HTTPS test with a bounded application-readiness
loop of up to 30 seconds.

Validated V0.7.2 SHA256:

``` text
69f93032461f7ca2372377bae77d13b6898237a2110e4eb353b8d419a0a9b566
```

Final automated validation result:

``` text
restored TLS certificate/private key match: PASS
restored TLS certificate currently valid:  PASS
nginx configuration test:                  PASS
waptserver active:                         PASS
wapttasks active:                          PASS
local HTTPS through historical FQDN:       HTTP 200
repository validation:                     PASS
```

The restore reported:

``` text
RESTORE VALIDATION PASSED
Database, configuration/identity, repository, TLS identity and local WAPT
service startup are validated.
```

The exact validated script was committed and pushed:

``` text
bb05f691 Complete validated WAPT server DR restore
branch: build/debian10-buster
```

The restore tool remains versioned:

``` text
tools/waptserver-restore.sh
SCRIPT_VERSION="0.7.2"
```

Do not silently call it V1.0 yet. Promotion/freezing as Restore V1.0 is a
separate explicit release action.

## 40. WAPT DR architecture — service identity transplant

The validated DR model is now explicitly:

``` text
transplant the logical WAPT service identity and data
onto a fresh supported target OS installation
```

It is **not** a requirement to clone the original Linux machine identity.

The critical continuity objects are:

``` text
WAPT database
server_uuid
secret_key
wapt_password
historical identity/policy configuration
client CA certificate/private key where applicable
server HTTPS/TLS certificate/private key
historical repository and Packages index
package-prefix continuity
authorized package-certificate policy
```

The administrator's historical WAPT package-signing private key is a separate
external administrative asset and is not expected inside the WAPT server
backup.

### 40.1 FQDN, hostname and IP rules

The historical WAPT **service FQDN** must remain stable from the clients'
perspective:

``` text
scrab.genevoix-signoret-vinci.fr.lan
```

The target Linux hostname does not need to be identical to the historical OS
hostname. The validated laboratory target proves that
`wapt-deb10.genevoix-signoret-vinci.fr.lan` can host the restored logical
`scrab` WAPT identity.

The IP address is likewise not intrinsically part of WAPT service identity.
A replacement server may use a different IP if production DNS maps the
historical WAPT service FQDN to the intended restored server and firewall/ACL
rules permit the required traffic.

Preserving the historical IP can still simplify environments where clients,
firewalls or other infrastructure contain literal IP references, but this is
an environmental compatibility issue rather than a WAPT identity requirement.

Future backup-format evolution should record an explicit:

``` text
service_fqdn=
```

instead of requiring restore-time derivation from the TLS certificate CN.

### 40.2 Mandatory pre-production cutover barrier

The restore tool deliberately does **not** change production DNS or authorize
production-client reconnection.

Before cutover, explicitly validate:

``` text
1. historical WAPT service FQDN resolves to the intended restored server;
2. network/firewall/ACL rules permit intended client traffic;
3. TLS identity presented for that FQDN is the intended restored/renewed cert;
4. authorized WAPT package certificates are reviewed;
5. the intended external package-signing key/certificate is available;
6. waptagent.exe is regenerated from the current console;
7. the current <prefix>-waptupgrade package is generated/published;
8. at least one historical client is validated before broad reconnection.
```

Current laboratory DNS resolution observed during V0.7.2:

``` text
scrab.genevoix-signoret-vinci.fr.lan -> 172.20.127.81
```

This was informational only and was not changed by the restore script.

During service validation, some existing clients attempted connections and
produced certificate-signature authentication failures. This does not invalidate
the local restore PASS, but reinforces the requirement to keep production
reconnection behind the explicit DNS/network/trust cutover barrier.

## 41. Debian 10 DR status — automated restore milestone closed

The following chain is now validated:

``` text
evolved WAPT 7398 Backup V1.0
    -> format-1 archive + sidecar integrity validation
    -> target precheck and dynamic PostgreSQL detection
    -> lightweight target safety backup
    -> logical DB restore / resume detection
    -> targeted ownership + schema ACL repair
    -> selective historical configuration/identity restore
    -> historical CA/TLS restore
    -> historical repository restore
    -> preserve target waptsetup-tis.exe / waptdeploy.exe
    -> operational permission normalization
    -> controlled WAPT service startup
    -> historical service-FQDN/TLS validation
    -> local HTTPS HTTP 200
    -> explicit pre-production cutover barrier
```

Together with the earlier manual historical DR and authentic VM104
7393 -> 7402 client migration, this establishes a reproducible Debian 10 DR
architecture.

Frozen/validated backup tool:

``` text
tools/waptserver-backup.sh
SCRIPT_VERSION="1.0"
SHA256 db8f75aa04fad3e7aa1419e446ddcf3fa19716565237e9ef3a7bde3a5fd8eede
commit 226b2cc1
```

Validated restore implementation:

``` text
tools/waptserver-restore.sh
SCRIPT_VERSION="0.7.2"
SHA256 69f93032461f7ca2372377bae77d13b6898237a2110e4eb353b8d419a0a9b566
commit bb05f691
```

Do not rewrite the validated intermediate commits:

``` text
c7f98b36  target safety backup
cbc158fc  logical database restore
74bbf2ae  repository restore
bb05f691  complete restore validation
```

## 42. Modernization roadmap — post Debian 10 DR

The objective is to minimize the number of compatibility transitions required
to move the nine historical Debian 10 / WAPT 1.8.2.7393 installations to a
maintainable platform without breaking client/package continuity.

Planned workstreams:

``` text
A. Close/freeze Debian 10 DR tooling and documentation.
B. Consolidate the validated Windows and Debian lineages as WAPT 1.8.3.
C. Validate real 7393 -> 1.8.3 server/client migration.
D. Provide autonomous installation/distribution:
     - synchronized Git/artifact path, and/or
     - project-owned APT repository.
E. Revisit final Windows Authenticode signing; keep lab signatures distinct
   from production distribution trust.
F. Implement explicit idempotent DB marker migration from 1.8.2.1 to at least
   1.8.3.0 for the consolidated release.
G. Validate Debian 10 -> Debian 11.
H. Validate Debian 11 -> Debian 12.
I. Evaluate direct restoration of a Debian 10 WAPT backup onto a fresh
   Debian 12 target as a possible simpler migration path than chained
   in-place OS upgrades.
J. Inventory and modernize COTS/security dependencies:
     Python runtime, OpenSSL, cryptography, mORMot, FPC/Lazarus and related
     libraries/CVEs.
K. Migrate the server from Python 2 to Python 3 with explicit compatibility
   testing.
L. Assess a later Python 3 Windows client migration separately from the
   server migration; do not assume they must occur simultaneously.
M. Maintain a compatibility matrix covering:
     server version;
     agent version;
     console version;
     package format/trust;
     Python runtime;
     Debian version;
     PostgreSQL/database marker.
N. Industrialize reproducible builds, automated validation, portable DR,
   documentation and later CI/CD.
```

Do not decide the exact ordering of Python 3, Debian 12 and major COTS/OpenSSL
changes until dependency/compatibility analysis is performed. Preserve the
smallest safe number of intermediate releases.

The first consolidated autonomous release remains:

``` text
1.8.3
```

The validated Windows 1.8.2.7402 artifacts remain signed with the temporary
self-signed laboratory Authenticode certificate. Before final autonomous
distribution, explicitly choose and validate the production signing strategy.

## 43. Exact next action — new-thread resume point

The Debian 10 disaster-recovery milestone is now frozen and documented.

Frozen DR components:

- Backup V1.0:
  - script: `tools/waptserver-backup.sh`
  - commit: `226b2cc1`
  - SHA256:
    `db8f75aa04fad3e7aa1419e446ddcf3fa19716565237e9ef3a7bde3a5fd8eede`
- Restore V1.0:
  - script: `tools/waptserver-restore.sh`
  - commit: `50246dd1f95036ebb0b2a7cd27004deadac5a76a`
  - tag: `server-buster-restore-v1.0`
  - SHA256:
    `06ff15a4b12b1c92b8f7885a5244e64a1859427093fbfcc19a986b77acdd2270`
- Complete operational DR procedure:
  - document: `WAPT_DR_DEBIAN10.md`
  - commit: `46f0bb671`
  - covers Backup V1.0, Restore V1.0, restore validation,
    pre-production cutover barrier, client reconnection, trust assets and
    operational limitations.

The pre-production FQDN/DNS/TLS/client-reconnection barrier is mandatory.

The validated historical WAPT TLS certificate expires on 2027-12-03 and must
be renewed or replaced before that date while preserving the WAPT service
FQDN semantics.

The next milestone is:

    REUNIFY THE VALIDATED DEBIAN AND WINDOWS LINEAGES FOR WAPT 1.8.3

Resume in this order:

    1. Reunify the validated Debian and Windows source lineages.
    2. Prepare the first consolidated autonomous release as 1.8.3.
    3. Implement the explicit DB marker migration to at least 1.8.3.0.
    4. Build all server/setup/client artifacts from the common release state.
    5. Re-evaluate final Windows Authenticode signing.
    6. Validate authentic 7393 -> 1.8.3 migration.
    7. Only after the consolidated Debian 10 release is validated, begin the
       Debian 11 phase.

Do not begin Debian 11 before the 1.8.3 consolidation milestone is closed.

## 44. Resume protocol for the next ChatGPT thread

Attach this checkpoint and send:

``` text
Gipity, on reprend le projet WAPT à partir du checkpoint joint.
Considère WAPT_CHECKPOINT.md comme l'état technique faisant autorité.
Le jalon DR Debian 10 Backup V1.0 + Restore V1.0 est gelé et documenté
dans WAPT_DR_DEBIAN10.md, commit 46f0bb671.
On reprend à la section "Exact next action" pour la réunification des
lignées Debian et Windows en vue de WAPT 1.8.3.
Réponses courtes, une étape à la fois.
```

VM106 remains the authoritative checkpoint working tree:

``` text
C:\git\waptdev\WAPT_CHECKPOINT.md
```

Wapster's untracked `WAPT_CHECKPOINT.md` remains an obsolete duplicate and
must not be committed.
