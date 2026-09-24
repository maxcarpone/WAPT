# WAPT Community 1.8.3 --- Windows Build Environment

## Purpose

This document defines the controlled Windows build environment for WAPT
Community 1.8.3.

The objective is to rebuild WAPT on a clean Windows machine from:

1.  the controlled WAPT Git repository and its Community submodules;
2.  the controlled `C:\wapt-build-kit`;
3.  documented build commands.

The historical VM106 environment is a reference used to establish the
baseline, not a required build dependency.

## Principles

-   Community edition only.
-   Build number = natural reachable Git commit count.
-   Do not run historical `init_workdir.bat`.
-   Do not use `git add .`.
-   Do not silently download or upgrade dependencies during a release
    build.
-   Prefer offline, hash-controlled inputs.
-   Keep the reproducible historical baseline distinct from later
    toolchain modernization.
-   Python 2 is transitional compatibility infrastructure, not the final
    architecture.

## Repository baseline

Current modernization branch:

`release/1.8.3`

Validated dependency-chain milestone:

-   parent commit: `9cc639f881a88b112c61d12a8a0d1d3085940b9f`
-   natural Git count: `7440`
-   16 Community submodules independently clonable from controlled
    GitHub repositories
-   isolated Lazarus PCP build: 9/9 projects PASS

The build script must derive the build number from Git; it must not
force an arbitrary number.

## Controlled build-kit

Expected root:

`C:\wapt-build-kit`

### Git

`git\Git-2.55.0.5-64-bit.exe`

SHA256:

`D065A4E23C3D9A6B5073D609B5BE0830227EC3CA053C083BA385061DDFAF94C6`

### CPython baseline

`python\python-2.7.18-x86.msi`

-   Python 2.7.18
-   x86 / 32-bit
-   MSI product version: 2.7.18150

SHA256:

`D901802E90026E9BAD76B8A81F8DD7E43C7D7E8269D9281C9E9DF7A9C40480A9`

The historical bootstrap used `C:\Python27`, but the assembled runtime
must not depend on it at execution time.

### Lazarus/FPC baseline

`lazarus\lazarus-1.8.2-fpc-3.0.4-win32.exe`

SHA256:

`B91517C673453F5AA355FFB3952E040433A8CDBBC5239BE72C869B60131B4166`

This is the reproducible baseline, not the permanent modernization
target. Later work should test newer Lazarus/FPC versions independently,
one change at a time.

### Inno Setup baseline

`inno-setup\innosetup-5.6.0-unicode.exe`

SHA256:

`84A97B5820F83E7EB7258B69CC857C4F446DFB5C7C337C35E05A0CC304729346`

A clean silent installation reproduced all 11 WAPT-used Inno Setup files
bit-for-bit compared with VM106.

This is a reproducible baseline, not the permanent modernization target.

### Python wheel inputs

Source wheelhouse:

`python\wheelhouse`

-   85 files
-   manifest: `python\wheelhouse-SHA256.txt`
-   manifest SHA256:
    `FE4F2DAD7754875758F98E6F7E96FF9AD6771432756E55A0291890983BFAB5A0`

Prepared offline wheels:

`python\built-wheels`

-   85 files
-   manifest: `python\built-wheels-SHA256.txt`
-   manifest SHA256:
    `27D44C87C80712C64B565747FD816E119006DD68469BAECCC042F0F70A9A5CDB`

The prepared wheel set was built with `--no-cache-dir --no-index` from
the controlled wheelhouse.

### Python runtime BOM

`python\wapt-runtime-1.8.3-freeze.txt`

SHA256:

`6E83828FA2F8A17FF9D83505909D5CF580974E2AE01EF899912D3711789D7E9A`

Important: the freeze is a package BOM, not the complete assembly
recipe. It does not capture the standalone `active_directory.py`,
`ujson.pyd`, WAPT patches, CPython stdlib/DLLs, or root runtime DLLs.

### WAPT-specific Python inputs

`python\wapt-binaries\ujson-1.35.pyd`

SHA256:

`F481A7AFB2DF7D834C2537D3DFA5CE1B22C0C40A83F4BD73602270A728951739`

`python\wapt-binaries\active_directory-0.6.7.py`

SHA256:

`EDFE01A38139D79A2EAC7B6F409B0495A447536CBB004318811D5CAF5842A556`

`python\wapt-binaries\python27.dll`

SHA256:

`8C81C84548CE191B11390EBAA71397D23662593B1C113AAA0392E40FF0F9307A`

Target pywin32 for WAPT 1.8.3: **228**. pywin32 227 is retained only as
a historical/fallback reference.

Controlled pywin32 228 root DLLs:

-   `pythoncom27.dll` ---
    `074F23F9710BBCF1447763829C0E3D16AFA5502EFC6F784077CF334F28CEFFB7`
-   `pythoncomloader27.dll` ---
    `CC5BA5439CFA435FC9BD442F6509EBDF83646DF0756093DFF6777775FD2246E6`
-   `pywintypes27.dll` ---
    `C4DB872FF7D301186516882EA06422AEE29E1C11B44A4D382ADDD5B801207818`

Historical pywin32 227 installer retained for reference:

`python\wapt-binaries\pywin_install.exe`

SHA256:

`23DDE7D8F6F5F2EBEC7209296C53367168926B1CA2B2734E0D481C782AC2937B`

MD5:

`D059126A23A6D55B5198B271BD29DDC1`

### OpenSSL external WAPT baseline

`runtime\openssl\openssl-1.0.2u-i386-win32.zip`

Archive SHA256:

`644FEDF6FC567716EF25F4FC805E2AAAC5BB7D32D01349EAEB62802CD20AE81A`

Extracted files validated bit-for-bit against VM106:

-   `openssl.exe` ---
    `6063E160E812F3D57B67B77581E30F110FDFC708F763BB2FCC82FA9CAAC816A3`
-   `libeay32.dll` ---
    `5264A4A478383F501961F2BD9BEB1F77A43A487B76090561BBA2CBFE951E5305`
-   `ssleay32.dll` ---
    `0A4031AB00664CC5E202C8731798800F0475EF76800122CEBD71D249655D725F`

Version: OpenSSL 1.0.2u, VC-WIN32.

This is the reproducible external WAPT OpenSSL baseline. It is separate
from the OpenSSL implementations used by CPython `ssl` and Python
`cryptography`.

### VC90 CRT

`runtime\vc90-crt`

Validated version: `9.00.30729.6161`

-   `Microsoft.VC90.CRT.manifest` ---
    `0C838C4262F99F27495A7C2A1BF4EC8F482D1C9BC2493C3C19B9360F1A06B8EB`
-   `msvcm90.dll` ---
    `7A74DA389FBD10A710C294C2E914DC6F18E05F028F07958A2FA53AC44F0E4B90`
-   `msvcp90.dll` ---
    `06918CF99AD26CD6CF106881C0D5BDB212DC0BAC4549805C9F5906E3D03D152C`
-   `msvcr90.dll` ---
    `8E7FE1A1F3550C479FFD86A77BC9D10686D47F8727025BB891D8F4F0259354C8`

### NSSM

`runtime\nssm`

Version: `2.24-103-gdee49fc`

-   win32 `nssm.exe` ---
    `BCE355F89B95D9F7C7441563D03A6CE6CD429DB865920F66561C0D90D1E0E285`
-   win64 `nssm.exe` ---
    `2900F26D2ED74F4D5DB77CBCCBD4F2185FCCE2625A1BE724120984AC2418989B`

### dmidecode

`runtime\tools\dmidecode.exe`

SHA256:

`7E14292571834665F0788C1BDE495421F704FAB74679127CBE35AF65714587F2`

## Validated autonomous Python/WAPT runtime

The reconstructed runtime was validated at:

`C:\wapt-runtime-1.8.3-assembled`

Validated properties:

-   Python 2.7.18 x86
-   `waptpython.exe` loads local `python27.dll`
-   no `C:\Python27` entry in `sys.path`
-   no `PYTHONPATH` required
-   CPython stdlib and native DLLs local
-   pywin32 228 PASS
-   Windows Python modules PASS
-   WAPT cryptography and SocketIO patches applied
-   `ujson` 1.35 PASS
-   `active_directory` 0.6.7 PASS
-   `waptutils` reports 1.8.3
-   `waptcrypto`, `waptpackage`, `setuphelpers`, `common` imports PASS
-   tests run from `C:\Windows\Temp`, outside the Git checkout
-   `wapt-get.py --help` exits 0
-   external WAPT OpenSSL runs locally and reports OpenSSL 1.0.2u

This proves runtime autonomy on VM106. It does **not yet** replace the
final clean-VM proof.

## WAPT patches required by the runtime

The historical bootstrap applies WAPT-provided patches after Python
dependency installation.

Required files come from the WAPT repository:

-   `utils\patch-socketio-client-2\__init__.py`
-   `utils\patch-socketio-client-2\transports.py`
-   `utils\patch-cryptography\__init__.py`
-   `utils\patch-cryptography\verification.py`

These are part of the controlled source tree and must be applied by the
replacement assembly script.

## WAPT core files copied to the runtime root

The setup definition requires, and the autonomous-core test validated,
the following source files:

-   `waptutils.py`
-   `waptcrypto.py`
-   `common.py`
-   `waptpackage.py`
-   `wapt-get.py`
-   `keyfinder.py`
-   `setuphelpers.py`
-   `setuphelpers_windows.py`
-   `setuphelpers_linux.py`
-   `setuphelpers_unix.py`
-   `setuphelpers_macos.py`
-   `windnsquery.py`
-   `custom_zip.py`

## VCForPython27 status

VM106 has Microsoft Visual C++ Compiler Package for Python 2.7 version
9.0.1.30729.

It is **not** currently part of the controlled build-kit.

The prepared `built-wheels` are intended to avoid native compilation on
a clean machine. Do not declare the compiler unnecessary until the
complete reconstruction succeeds on a clean Windows VM without it.

## Historical init_workdir.bat

`init_workdir.bat` must not be run as-is.

Problems include:

-   destructive `git clean -xfd`;
-   mutable live `pip` upgrades;
-   Internet dependency resolution;
-   fixed `C:\Python27` assumptions;
-   direct mutation of the source checkout;
-   historical pywin32 227 installation;
-   old download/bootstrap behavior through `update_binaries.py`.

Its useful behavior has been treated as a specification and is being
replaced by `tools\02-build-windows-runtime.ps1`.

## Baseline versus modernization

The first objective is a deterministic WAPT Community 1.8.3 build using
known-good inputs.

Once that is reproducible on a clean machine, modernize components
independently and validate after each change. Candidate work includes:

-   Lazarus 1.8.4, then an appropriate 2.0.x or newer toolchain;
-   newer Inno Setup;
-   replacement/modernization of external OpenSSL 1.0.2u;
-   eventual removal of Python 2.

Do not mix those upgrades into the clean-baseline proof.
