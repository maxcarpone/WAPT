# WAPT Community 1.8.3 --- Windows Build and Release Procedure

## Scope

This procedure describes the controlled Windows reconstruction path for
WAPT Community 1.8.3.

It replaces the historical `init_workdir.bat` workflow. The immediate
objective is deterministic reconstruction; toolchain modernization
follows only after the baseline is proven on a clean Windows machine.

## Inputs

Required:

-   controlled WAPT Git clone on `release/1.8.3`;
-   exact Community submodules initialized from controlled GitHub
    repositories;
-   `C:\wapt-build-kit`;
-   Python 2.7.18 x86 installed temporarily as the bootstrap
    interpreter;
-   Lazarus/FPC baseline for the baseline build;
-   Inno Setup baseline installer;
-   signing material only for the signing stage.

Do not use live Internet package resolution during runtime assembly.

## Phase 1 --- Verify source state

From the WAPT repository:

``` powershell
git status --short
git rev-parse HEAD
git rev-list --count HEAD
git submodule status
```

The build number is the natural `git rev-list --count HEAD` result.

Never force a build number manually.

## Phase 2 --- Initialize Community dependencies

Initialize only the 16 known Community submodules. Do not use a blind
recursive update that attempts Enterprise-only/dead dependencies.

The controlled Git dependency chain was validated at parent commit:

`9cc639f881a88b112c61d12a8a0d1d3085940b9f`

with natural count `7440`.

## Phase 3 --- Assemble the autonomous Python runtime

Use:

``` powershell
powershell -ExecutionPolicy Bypass -File .\tools\build-windows-runtime.ps1 `
    -BuildKit C:\wapt-build-kit `
    -BootstrapPython C:\Python27\python.exe `
    -Output C:\wapt-runtime-1.8.3
```

The script must:

1.  refuse unsafe output locations;
2.  verify critical controlled-input hashes;
3.  create an isolated Python 2.7 virtual environment;
4.  install packages only from controlled `built-wheels`;
5.  install pywin32 228;
6.  inject controlled `ujson` and `active_directory`;
7.  apply WAPT SocketIO and cryptography patches;
8.  copy the full CPython 2.7 stdlib and DLL directories into the
    runtime;
9.  remove `orig-prefix.txt`;
10. copy controlled root Python/pywin32 DLLs;
11. create `waptpython.exe` and `waptpythonw.exe`;
12. copy the WAPT core Python files;
13. add controlled external OpenSSL;
14. validate runtime autonomy.

The bootstrap `C:\Python27` installation is allowed during assembly. The
resulting runtime must not depend on it at execution time.

## Phase 4 --- Runtime acceptance checks

With `PYTHONPATH` removed and current directory outside the repository:

-   `sys.prefix` points to the assembled runtime;
-   `sys.path` contains no `C:\Python27`;
-   loaded `python27.dll` comes from the runtime root;
-   stdlib/native DLL imports PASS;
-   pywin32 228 imports PASS;
-   `waptcrypto`, `waptpackage`, `setuphelpers`, `common` PASS;
-   `waptutils.__version__ == "1.8.3"`;
-   `wapt-get.py --help` returns 0;
-   external `openssl.exe version` returns 0 and reports 1.0.2u for the
    baseline.

## Phase 5 --- Prepare Lazarus environment

Use a fresh Lazarus primary config path (PCP), not the historical user
profile.

Register the 18 validated packages from the clean controlled clone.

The 9 Community projects are:

1.  `wapt-get\waptget.lpi`
2.  `wapt-get\WaptGuiHelper.lpi`
3.  `waptdeploy\waptdeploy.lpi`
4.  `wapttray\wapttray.lpi`
5.  `waptconsole\waptconsole.lpi`
6.  `waptexit\waptexit.lpi`
7.  `waptself\waptself.lpi`
8.  `waptmessage\waptmessage.lpi`
9.  `waptsetup\waptsetuputil\waptsetuputil.lpi`

Historical validated invocation pattern:

``` powershell
C:\wapt-build-test\Scripts\python.exe .\lazbuild.py `
    -p C:\tmp\wapt-lazarus-clean `
    -e community `
    -v 1.8.3 `
    <project.lpi>
```

Do not pass `-b`.

A clean isolated build at parent count 7440 produced all 9 projects
successfully with FileVersion 1.8.3.7440 and ProductVersion 1.8.3.

## Phase 6 --- Populate product-level external binaries

From the controlled build-kit, populate the WAPT product tree with:

-   external OpenSSL 1.0.2u baseline;
-   VC90 CRT 9.0.30729.6161 and corrected manifest;
-   `dmidecode.exe`;
-   NSSM win32 and win64.

Do not source these from an old working checkout once the build-kit is
available.

## Phase 7 --- Reconstruct Inno Setup tree

Install/extract the controlled Inno Setup 5.6.0 Unicode installer into a
temporary directory.

The following 11 files were proven bit-identical to the historical WAPT
tree:

-   `isbunzip.dll`
-   `isbzip.dll`
-   `ISCC.exe`
-   `ISCmplr.dll`
-   `islzma.dll`
-   `islzma32.exe`
-   `islzma64.exe`
-   `ISPP.dll`
-   `isscint.dll`
-   `isunzlib.dll`
-   `iszlib.dll`

Populate `waptsetup\innosetup` from this controlled installation rather
than preserving an opaque historical copy.

## Phase 8 --- Generate version metadata

Generate `version-full` and `revision.txt` using the controlled
runtime/build procedure.

Do not commit generated build residue unless the release process
explicitly requires a tracked file.

## Phase 9 --- Build setup

Compile:

`waptsetup\waptsetup.iss`

with the controlled `ISCC.exe`.

The setup consumes the assembled Python runtime, WAPT core/service
files, Lazarus outputs, external OpenSSL, CRT, NSSM and other controlled
source assets defined by the `.iss` files.

## Phase 10 --- Signing

The historical 1.8.2.7402/1.8.3 validation used a temporary self-signed
lab Authenticode certificate.

That certificate is for lab validation only.

Before final public release, define and validate the production signing
strategy. Preserve `uiAccess=true`; do not weaken the manifest merely to
avoid signing requirements.

## Phase 11 --- Clean-machine proof

The decisive acceptance test is a fresh Windows machine with no
inherited VM106 WAPT environment.

Starting only with the controlled build-kit and controlled Git clone:

1.  install only explicitly documented build prerequisites;
2.  assemble the autonomous Python runtime;
3.  initialize Community submodules;
4.  prepare isolated Lazarus PCP;
5.  build all 9 Lazarus projects;
6.  reconstruct Inno Setup files;
7.  populate controlled external binaries;
8.  build the setup;
9.  sign using the selected test/release method;
10. validate setup and agent behavior.

A successful clean-machine run determines whether VCForPython27 is
actually unnecessary when using the prepared wheels.

## Phase 12 --- Modernization after baseline proof

After the clean baseline is reproducible, modernize one component at a
time.

Do not combine toolchain upgrades into the baseline proof.

Candidate order:

1.  test Lazarus 1.8.4;
2.  evaluate Lazarus 2.0.x or another suitable newer version;
3.  test a newer Inno Setup;
4.  modernize/remove external OpenSSL 1.0.2u;
5.  later migrate away from Python 2.

Each change requires compilation and runtime regression validation
before the next change.

## Release discipline

-   Community only.
-   Never `git add .`.
-   Do not commit temporary runtimes, compiler outputs or test setup
    artifacts accidentally.
-   Preserve upstream authorship/history/licenses.
-   Do not touch Enterprise dependencies.
-   Do not alter production systems during build reconstruction.
-   Do not freeze/tag the final 1.8.3 release until Debian migration/DR,
    Windows setup/agent publication, signing, repository continuity and
    autonomous-distribution checks are complete.
