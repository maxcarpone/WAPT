# WAPT 1.8.2 Modernization — Technical Checkpoint

**Checkpoint date:** 2026-09-15  
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

## 2. Main WAPT repository — authoritative state

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

### Build-number mechanism — RESOLVED

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

`pltis_synapse` is intentionally checked out at a public commit different from the parent repository's historical/private gitlink. Do not “fix” or commit it accidentally.

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

## 4. SoGrid — FINAL 7402 STATE

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

## 9. Portal agent publication — RESOLVED FOR LAB

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

## 11. Windows Lazarus build chain — FINAL 7402

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

## 12. VC90 CRT — RESOLVED

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

## 13. Authenticode signing — FINAL 7402

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

## 14. version-full — FINAL 7402

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

Physical package presence and repository metadata were validated. Do not reopen “package/index missing” without contradictory evidence.

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

## 17. WAPTConsole functional validation — FINAL 7402

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

The SoGrid “Paquets disponibles” defect is considered resolved for 7402.

## 18. Production-style Windows migration validation — PASS

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

**PASS — production-style Windows migration from authentic WAPT 1.8.2.7393 to the rebuilt WAPT 1.8.2.7402 is validated.**

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

## 19. UnknownIssuer diagnostic episode — NON-BLOCKING / CLOSED

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

## 21. Open work after the 7402 Windows milestone

The Windows 7402 Community build/release/migration chain is now validated. Do not continue treating it as the primary blocker.

Remaining work should focus on release preservation/reproducibility and the server migration path.

Priority areas:

1.  **Preserve the 7402 release state**

    - commit this checkpoint only;
    - push the three already-validated technical commits plus the checkpoint;
    - preserve hashes, package metadata and build procedure;
    - ensure private signing material remains outside Git.

2.  **Server migration/release path**

    - decide/validate the exact production upgrade procedure for the 9 existing Debian 10 / WAPT 7393 servers;
    - validate the rebuilt Debian 10 server package against a production-like upgrade, not only a fresh lab install;
    - preserve rollback/backups and PostgreSQL migration procedure;
    - later move through Debian 11 and Debian 12.

3.  **Server cleanup**

    - fresh DB version marker `1.8.2.0` vs historical `1.8.2.1`;
    - make local setup/agent publication explicit and reproducible;
    - remove dependency on obsolete external setup fallback where appropriate.

4.  **Build reproducibility**

    - document/recreate Lazarus package setup and inaccessible/private submodule substitutions;
    - keep Synapse divergence explicit;
    - optionally clean SoGrid history against the now-restored official history, but **not as part of 7402**.

5.  **Later modernization**

    - Python 3 package/runtime migration remains deferred until the transitional WAPT 1.8.2 chain is stable across the server migration path.

## 22. Exact next action

The immediate action after creating this file is **release-state preservation**, not another rebuild.

From:

``` text
WAPT HEAD before checkpoint: 895cb7597
Natural build: 7402
SoGrid: 540d1814813f2cd5a2445910989f50cfaf1a9228
Final setup SHA256: ADD5FC3F6D81E394FD821EAA3AC7A3D3543DA9438C2AA474FAAE2B95DD41083C
Final upgrade package: deb10-waptupgrade 1.8.2.7402-49
Windows migration validation: PASS
```

Next steps:

``` text
1. Replace WAPT_CHECKPOINT.md with this checkpoint.
2. Review `git diff -- WAPT_CHECKPOINT.md`.
3. Stage only WAPT_CHECKPOINT.md.
4. Commit the checkpoint.
5. Push branch-1.8.2 so the validated technical commits and checkpoint are backed up remotely.
6. Re-check remote HEAD and working tree; only intentional Synapse divergence should remain.
7. Then begin the production-like Debian 10 server upgrade validation.
```

Important build-number consequence: committing this checkpoint will make the branch Git commit count 7403. That **does not invalidate the already-built 7402 artifacts** because they are tied to source commit `895cb7597`. Do not rebuild them merely because the documentation checkpoint adds a later commit.

## 23. Resume protocol for a new ChatGPT thread

Attach this checkpoint and send:

``` text
Gipity, on reprend le projet WAPT 1.8.2 à partir du checkpoint joint.
Considère WAPT_CHECKPOINT.md comme l'état technique faisant autorité.
Ne recommence pas les investigations déjà validées sauf si une contradiction apparaît.
On reprend à la section "Exact next action".
Réponses courtes, une étape à la fois.
```

If later work contradicts this file, update the checkpoint at the next major milestone instead of silently rewriting history.
