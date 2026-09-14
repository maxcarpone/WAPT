# WAPT 1.8.2 Modernization — Technical Checkpoint

**Checkpoint date:** 2026-09-14  
**Purpose:** authoritative save-state for resuming the project in a fresh ChatGPT thread without replaying the full historical conversation.

## 1. Project objective

Modernize the WAPT 1.8.2 Community codebase while preserving compatibility with existing deployments and a reproducible migration path.

Production context:
- 9 existing WAPT servers.
- Historical production OS: Debian 10.13 Buster.
- Historical production WAPT: 1.8.2.7393.
- Transitional Python 2 compatibility is intentional; Python 3 modernization is a later phase.
- Community edition is the target; Enterprise is not.

Target migration concept:
1. Debian 10 / WAPT 7393.
2. Debian 10 / new autonomous Python-2-compatible build.
3. Debian 11.
4. Debian 12 current transitional package/runtime.
5. Later Debian 13 / Python 3 modernization.

## 2. Main WAPT repository

Repository:
```text
https://github.com/maxcarpone/WAPT
```

Working tree:
```text
C:\git\waptdev
```

Current branch:
```text
branch-1.8.2
```

Current authoritative HEAD:
```text
0ea123e0bc2d8b6d406806b52827748a8f6720e7
```

Latest commit:
```text
0ea123e0b Use WAPT-compatible SoGrid fork
```

Remote state:
```text
origin/branch-1.8.2 == 0ea123e0bc2d8b6d406806b52827748a8f6720e7
```

Historical reference commits:
```text
75a5de09  historical build 7393
566bcad8  historical build 7394
4bbf306a  historical build 7395
74bfc5ef6 previous Windows/Lazarus compatibility milestone
0ea123e0b current checkpoint
```

Build-number warning: current console has shown 1.8.2.7400 after later Git commits, while the validated Debian Buster server package is 7397. Final build-number policy is not yet normalized.

## 3. Current Git working tree state

At checkpoint time:
```text
 M Microsoft.VC90.CRT.manifest
 M submodules/pltis_synapse
 M wapt-get/WaptGuiHelper.lpi
 M wapt-get/waptget.ico
 M wapt-get/waptget.lpi
 M wapt-get/waptguihelper.ico
 M waptconsole.sha256
 M waptconsole/waptconsole.ico
 M waptconsole/waptconsole.lpi
 M waptdeploy/waptdeploy.ico
 M waptdeploy/waptdeploy.lpi
 M waptexit/waptexit.ico
 M waptexit/waptexit.lpi
 M waptmessage/waptmessage.ico
 M waptmessage/waptmessage.lpi
 M waptself/waptself.lpi
 M waptsetup/waptsetuputil/waptsetuputil.ico
 M waptsetup/waptsetuputil/waptsetuputil.lpi
 M wapttray/wapttray.ico
 M wapttray/wapttray.lpi
?? version-full
?? wapt-lab-codesign.cer
?? wapt-lab-codesign.pfx
?? waptmessage.exe
?? waptmessage/lib/
?? waptself.exe
```

**Do not run `git add .`.** Many `.lpi`, `.ico`, hashes and binaries are build-side effects and must be reviewed individually. The lab signing certificate/private key are diagnostic artifacts only and must never be committed.

## 4. SoGrid reconstruction — authoritative state

The original parent repository referenced inaccessible/private SoGrid commit:
```text
d9766d181662fd59781a000997f19aeffcc3e0c2
```

Public Tranquil IT SoGrid lacked API/properties expected by WAPT 1.8.2 forms and Pascal code, so compatibility was reconstructed from WAPT usage.

Fork:
```text
https://github.com/maxcarpone/pltis_sogrid
```

Compatibility branch:
```text
wapt-1.8.2-compat
```

Authoritative SoGrid commit:
```text
68f6e98a63ce9db1769053ed5cbdef7e5d51509e
```

Commit message:
```text
Restore WAPT compatibility in SoGrid
```

Parent WAPT now records that gitlink and `.gitmodules` points SoGrid to the fork above.

Current submodule status snapshot:
```text
-68f6e98a63ce9db1769053ed5cbdef7e5d51509e submodules/pltis_sogrid
+14589d4b7b5886242552021e5a1a637b1ea4c82f submodules/pltis_synapse (heads/master)
```

Interpretation:
- SoGrid gitlink is correct in the parent, but the working copy is not currently initialized through normal `git submodule` metadata (`-` prefix).
- Synapse is checked out at a public commit different from the parent's inaccessible/private expected gitlink (`+` prefix).
- Do not “fix” either automatically.

### Reconstructed SoGrid compatibility changes

`source/sogrid.pas` includes:
1. `TDynStringArray` -> `TStringArray` in `TSOConnection.LoadData`.
2. Local `Offset` -> `LOffset` in `TSOStringEditLink.SetBounds`.
3. Public `procedure DeleteRows(SOArray: ISuperObject);` plus implementation.
4. `TSOGridNodesEvent` + published `OnNodesDelete`.
5. Published `KeyFieldsNames: String` as persistent storage.
6. `TSOGridSOCompareNodesEvent` + published `OnSOCompareNodes`.
7. `TSOGridBeforePasteEvent` + published `OnBeforePaste`.
8. `DoCompare` invokes `FOnSOCompareNodes`, passing property names split on `;`.
9. `DoDeleteRows` invokes `FOnNodesDelete(Self, todelete)`.
10. `DoPaste` lets `OnBeforePaste` veto each row.

Important limitation: this behavior was reconstructed from WAPT source/forms and runtime tests. It is not claimed to be identical to the inaccessible private historical SoGrid source. In particular, `DeleteRows`, `KeyFieldsNames`, and `OnSOCompareNodes` deserve continued functional testing.

### Encoding/EOL validation

An intermediate edit introduced a BOM and mojibake; it was discarded. Final committed source before commit was validated as:
```text
BOM  = False
CRLF = 4048
LF   = 0
git diff --check = clean
```

Avoid PowerShell `Set-Content` for these legacy Pascal files.

## 5. Other Lazarus submodules

Known inaccessible/private expected gitlinks include:

Synapse expected by parent:
```text
0b230215d388520e48a6de3b0c7d40d0a274d9cc5
```

Public Synapse checkout in use:
```text
14589d4b7b5886242552021e5a1a637b1ea4c82f
```

Therefore parent reports `submodules/pltis_synapse` modified. Do not commit accidentally.

LCL Extensions historical/private gitlink noted as:
```text
dba578...
```

BGRA packages registered:
```text
C:\git\waptdev\submodules\pltis_bgracontrolsfx\bgracontrolsfx.lpk
C:\git\waptdev\submodules\pltis_bgrabitmap\bgrabitmap\bgrabitmappack.lpk
C:\git\waptdev\submodules\pltis_bgracontrols\bgracontrols.lpk
```

Do not fork every `pltis_*` blindly; fork only where necessary for reproducibility or patches.

## 6. Debian 12 transitional Python 2 runtime

Reference host:
```text
Debian GNU/Linux 12.15 (bookworm)
Kernel 6.1.0-32-amd64
amd64 / x86_64
GCC 12.2.0
GNU Make 4.3
Python 3.11.2
OpenSSL 3.0.20
```

Python 2.7.18 was built from source. Consolidated runtime:
```text
/git/waptdev/build/python2-runtime-server
```

Earlier test runtimes:
```text
/opt/wapt-runtime-test
/opt/wapt-runtime-dependency-test
```

Key validated packages include:
```text
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

Additional resolved dependencies: `requests`, `psutil`, `netifaces`.

Known non-blocking absence:
```text
lzma
```

Validated:
- Python 2 SSL works with OpenSSL 3.0.20.
- `cryptography==2.5` works with the WAPT verification patch.
- `pyOpenSSL==19.0.0` imports.
- `waptcrypto` functional API loads.
- CA / CSR / client cert / signing / verification test passed.
- `waptserver` module imports.
- final runtime report: `All WAPT runtime tests passed.`

## 7. Debian server package state

Bookworm reference build branch/commit:
```text
build/debian12-bookworm
5da9f66b
```

Buster reference build branch/commit:
```text
build/debian10-buster
907d4e78
```

Validated Buster package:
```text
/git/waptdev/waptserver/deb/tis-waptserver-1.8.2.7397-907d4e78-debian-10-amd64.deb
```

SHA256:
```text
7445288003d062e7a8afa29d1b8395cdf0b3705b0bc526d49b3a17e214a37733
```

Installed version:
```text
1.8.2.7397-907d4e78-debian-10-amd64
```

Runtime:
```text
/opt/wapt/bin/python -> Python 2.7.18
```

## 8. Debian 10 lab server validation

Lab:
```text
hostname: wapt-deb10
FQDN: wapt-deb10.genevoix-signoret-vinci.fr.lan
IP: 192.168.220.12/22
gateway: 192.168.223.254
```

Fresh initial state: Debian 10, Python 3.7.3, no system Python 2, no PostgreSQL, no WAPT.

Installed Buster 7397 package + PostgreSQL 11 + nginx. Postconf:
```text
/opt/wapt/waptserver/scripts/postconf.sh
```

Lab registration mode selected: unauthenticated registration, WAPT 1.3 behavior.

Validated:
- waptserver active/enabled on localhost:8080;
- nginx on 80/443;
- PostgreSQL 11 on localhost:5432;
- role/database `wapt`;
- portal HTTPS reachable.

Fresh DB marker discrepancy:
```text
Fresh 7397 portal: OK (1.8.2.0)
Production 7393 historical screenshot: OK (1.8.2.1)
```

Investigation found fresh DB already contains `hostsyncstatus`; `init_db()` creates current schema but sets version from `__version__ = "1.8.2"`, which renders as 1.8.2.0. Decision: do not hand-edit DB now; fix code later.

## 9. Portal client download issue

Fresh lab portal offered historical WAPTSetup 1.8.2.7388. Server serves local `wapt/waptsetup-tis.exe` if present, otherwise falls back to historical external WAPT release URL. Future requirement: publish our validated setup locally and remove reliance on the old external binary.

## 10. Windows build workstation

```text
Windows 11 25H2 AMD64
Repo: C:\git\waptdev
Git: C:\Program Files\Git\cmd\git.exe (2.55.0.windows.5)
Python: C:\Python27 (2.7.18 x86)
Build venv: C:\wapt-build-test
Lazarus 1.8.2
FPC 3.0.4
Lazarus path: C:\lazarus
Inno Setup 5.6.0
ISCC: C:\git\binaries_cache\iscc\app\ISCC.exe
```

Historical OpenSSL 1.0.2u i386 was recovered for Windows build requirements.

NSSM restored:
```text
waptservice\win32\nssm.exe
waptservice\win64\nssm.exe
```

`ujson==1.35` built with VC9. WAPT crypto tests passed.

## 11. Windows Lazarus build chain

Expected projects:
1. `wapt-get\waptget.lpi`
2. `wapt-get\waptguihelper.lpi`
3. `waptdeploy\waptdeploy.lpi`
4. `wapttray\wapttray.lpi`
5. `waptconsole\waptconsole.lpi`
6. `waptexit\waptexit.lpi`
7. `waptself\waptself.lpi`
8. `waptmessage\waptmessage.lpi`
9. `waptsetup\waptsetuputil\waptsetuputil.lpi`

All nine compiled successfully during reconstruction.

`lazbuild.py -e community -v 1.8.2 -b <build>` rewrites product version/edition metadata. A test with `-b 7393` produced exact 1.8.2.7393 Community metadata. Direct lazbuild is useful for diagnostics, but wrapper builds should be used for final metadata.

Relevant commits:
```text
3882380d Fix Community waptconsole build without Enterprise units
74bfc5ef6 Fix waptexit build with Lazarus 1.8.2
```

`waptexit` compatibility fix replaced unsupported `ExtractFileNameWithoutExt(ExtractFileNameOnly(ParamStr(0)))` with `ExtractFileNameOnly(ParamStr(0))`.

## 12. VC90 runtime and Inno Setup

Inno initially lacked:
```text
msvcm90.dll
msvcp90.dll
msvcr90.dll
Microsoft.VC90.CRT.manifest
```

The current Microsoft VC++ 2008 SP1 x86 wrapper EXE is version 9.0.30729.5677, but its `vc_red.cab` contains the required 9.0.30729.6161 payloads. Those were extracted to repo root.

Direct Inno build succeeded:
```powershell
& "C:\git\binaries_cache\iscc\app\ISCC.exe" .\waptsetup\waptsetup.iss
```

## 13. Windows setup candidate validated

Candidate:
```text
C:\git\waptdev\waptsetup\waptsetup.exe
```

Metadata:
```text
FileVersion 1.8.2.7397
ProductVersion 1.8.2
ProductName WAPTSetup
```

SHA256:
```text
34FE693005F94AA4192C7971B1860263F29DC8912CC642CF7DB9FD928285340A
```

Initially unsigned.

## 14. Windows client lab validation

Lab client:
```text
Windows 11 25H2
IP 192.168.220.11
```

After removing an older WAPT installation, the candidate installed successfully under:
```text
C:\Program Files (x86)\wapt
```

Validated:
```text
wapt-get.exe --version -> Wrapper Win32.exe wapt-get 1.8.2.7397
Python modules -> 1.8.2
WAPTService -> Running, Automatic
wapt-get update -> success
wapt-get register -> success
```

Core Windows client/server communication works.

## 15. waptconsole launch blocker and signing diagnosis

Initial rebuilt `waptconsole.exe` failed on Windows 11 25H2 with:
```text
Une référence a été renvoyée par le serveur.
```

Manifest:
```xml
<requestedExecutionLevel level="asInvoker" uiAccess="true"/>
```

Rebuilt executable was unsigned; historical working consoles were signed. Decision: do not change `uiAccess`; restore signing.

Windows SDK SignTool installed:
```text
C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe
```

LAB certificate:
```text
Subject: CN=WAPT Lab Code Signing
Thumbprint: D8B8C49EEB204125D7609365D4CF604E8B7056AC
```

Lab files:
```text
C:\git\waptdev\wapt-lab-codesign.pfx
C:\git\waptdev\wapt-lab-codesign.cer
```

Never commit them.

After manual SHA-256 signing and trusting the lab cert in LocalMachine Root + TrustedPublisher, the launch blocker disappeared. Therefore signing is required for current `uiAccess=true` behavior. Production release must sign internal EXEs before packaging, then sign final setup.

Historical `lazbuild.py` uses legacy signing syntax with `/t`. Future modernization should add `/fd SHA256` and preferably RFC3161 `/tr` + `/td SHA256`, subject to production certificate compatibility.

## 16. Current waptconsole functional validation

After SoGrid reconstruction, rebuild and signing, console successfully:
- launches on Windows 11 25H2;
- displays Community Edition;
- authenticates to Debian 10 lab server;
- opens main console;
- generates a certificate;
- generates a WAPT agent;
- creates the update package;
- uploads generated artifacts to main repository.

Observed UI version:
```text
waptconsole Community Edition 1.8.2.7400
```

Agent-generation success message confirmed both agent and update package creation/upload.

This is a major functional milestone.

## 17. SoGrid serialized property inventory

Direct TSOGrid properties/events used by WAPT `.lfm` files include:
```text
Align, Alignment, Anchors, BorderStyle, ChangeDelay, Color, DragMode, DragType,
Height, HintMode, Images, KeyFieldsNames, Left, OnBeforePaste, OnChange, OnClick,
OnColumnDblClick, OnColumnResize, OnDblClick, OnDragAllowed, OnDragDrop, OnDragOver,
OnDrawText, OnEdited, OnEditing, OnFocusChanged, OnGetHint, OnGetImageIndexEx,
OnGetText, OnHeaderClick, OnHeaderDblClick, OnHeaderDragged, OnInitNode, OnKeyPress,
OnMeasureItem, OnNewText, OnNodesDelete, OnPaintText, OnSOCompareNodes, PopupMenu,
ShowAdvancedColumnsCustomize, TabOrder, Top, WantTabs, Width, ZebraPaint
```

After reconstruction, all direct TSOGrid properties used by WAPT forms are represented.

## 18. Known-good build commands

SoGrid package:
```powershell
cd C:\tmp\pltis_sogrid-wapt-clean
& "C:\lazarus\lazbuild.exe" .\pltis_sogrid.lpk
```

Direct diagnostic waptconsole rebuild:
```powershell
& "C:\lazarus\lazbuild.exe" `
  --primary-config-path="C:\Users\Maintenance\AppData\Local\lazarus" `
  -B `
  "C:\git\waptdev\waptconsole\waptconsole.lpi"
```

Use `lazbuild.py` rather than bare lazbuild for final version metadata.

## 19. Dangerous / misleading operations

Avoid:
```text
git add .
```

Avoid `Set-Content` on legacy Pascal/source files where encoding/EOL matter.

Lazarus rewrites `.lpi` files; do not assume those diffs are intentional.

`core.autocrlf` is intentionally false.

Do not commit lab signing keys/certs/passwords.

Do not remove `uiAccess=true` merely to bypass signing; signing already proved to solve the launch issue.

## 20. Open work

Highest priority: complete and normalize the Windows build/release chain.

Tasks:
1. decide authoritative build-number strategy;
2. rebuild all nine internal executables with final metadata;
3. sign all internal executables;
4. build final installer;
5. sign final installer;
6. validate clean install and upgrade behavior;
7. validate generated agent on a clean machine.

SoGrid tests still desirable:
- deletion / `DeleteRows`;
- `OnNodesDelete`;
- sorting via `OnSOCompareNodes`;
- paste filtering via `OnBeforePaste`;
- row identity/focus potentially related to `KeyFieldsNames`.

Submodules: make remaining inaccessible/private dependencies reproducible, especially Synapse and LCL Extensions. Do not fork every `pltis_*` blindly.

Server later:
- fix fresh DB version-marker behavior;
- serve our own current WAPT setup locally;
- remove fallback to historical external setup;
- validate production migration path.

Python 3 remains deferred until the transitional WAPT 1.8.2 chain is stable.

## 21. Exact next action

Resume Windows functional validation/release cleanup from:
```text
WAPT   0ea123e0bc2d8b6d406806b52827748a8f6720e7
SoGrid 68f6e98a63ce9db1769053ed5cbdef7e5d51509e
```

Do not reopen solved SoGrid reconstruction unless a contradiction appears.

Recommended immediate action: **test the freshly generated WAPT agent on a clean Windows client before freezing the final release build.**

## 22. Resume protocol for a new ChatGPT thread

Attach this checkpoint and send:

```text
Gipity, on reprend le projet WAPT 1.8.2 à partir du checkpoint joint.
Considère WAPT_CHECKPOINT.md comme l'état technique faisant autorité.
Ne recommence pas les investigations déjà validées sauf si une contradiction apparaît.
On reprend à la section "Exact next action".
Réponses courtes, une étape à la fois.
```

If later work contradicts this file, update the checkpoint at the next major milestone instead of silently rewriting history.
