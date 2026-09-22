#requires -Version 5.1
<#
.SYNOPSIS
  Assemble the autonomous Python/WAPT runtime for WAPT Community 1.8.3.

.DESCRIPTION
  Controlled replacement for the runtime-assembly portions of historical
  init_workdir.bat. It deliberately does NOT:
    - git clean the repository
    - download dependencies
    - upgrade pip/setuptools from the Internet
    - build Lazarus projects
    - build the Inno Setup installer
    - sign binaries

  Baseline assumptions:
    - bootstrap CPython 2.7.18 x86 is installed temporarily
    - C:\wapt-build-kit contains the validated controlled inputs
    - this script is run from a WAPT 1.8.3 source tree

  The resulting runtime is expected to execute without C:\Python27 in sys.path.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepoRoot = "",

    [Parameter()]
    [string]$BuildKit = "C:\wapt-build-kit",

    [Parameter()]
    [string]$BootstrapPython = "C:\Python27\python.exe",

    [Parameter()]
    [string]$Output = "C:\wapt-runtime-1.8.3",

    [switch]$Force
)

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text"
}

function Assert-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }
}

function Assert-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Required directory missing: $Path"
    }
}

function Assert-Sha256([string]$Path, [string]$Expected) {
    Assert-File $Path
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw "SHA256 mismatch for $Path`nExpected: $Expected`nActual:   $actual"
    }
}

function Copy-Checked([string]$Source, [string]$Destination, [string]$Sha256) {
    Assert-Sha256 $Source $Sha256
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Assert-Sha256 $Destination $Sha256
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter()][string[]]$Arguments = @()
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

# ---------------------------------------------------------------------------
# Controlled inputs
# ---------------------------------------------------------------------------

$BuiltWheels = Join-Path $BuildKit "python\built-wheels"
$WaptBins    = Join-Path $BuildKit "python\wapt-binaries"
$OpenSslZip  = Join-Path $BuildKit "runtime\openssl\openssl-1.0.2u-i386-win32.zip"

$Python27Dll = Join-Path $WaptBins "python27.dll"
$PythonCom   = Join-Path $WaptBins "pywin32-228\pythoncom27.dll"
$PythonComL  = Join-Path $WaptBins "pywin32-228\pythoncomloader27.dll"
$PyWinTypes  = Join-Path $WaptBins "pywin32-228\pywintypes27.dll"
$Ujson       = Join-Path $WaptBins "ujson-1.35.pyd"
$ActiveDir   = Join-Path $WaptBins "active_directory-0.6.7.py"

$ReqGeneric  = Join-Path $RepoRoot "requirements-agent.txt"
$ReqWindows  = Join-Path $RepoRoot "requirements-agent-windows.txt"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

Write-Step "Preflight"

Assert-File $BootstrapPython
Assert-Dir $RepoRoot
Assert-Dir $BuiltWheels
Assert-File $ReqGeneric
Assert-File $ReqWindows

Assert-Sha256 $Python27Dll "8C81C84548CE191B11390EBAA71397D23662593B1C113AAA0392E40FF0F9307A"
Assert-Sha256 $PythonCom   "074F23F9710BBCF1447763829C0E3D16AFA5502EFC6F784077CF334F28CEFFB7"
Assert-Sha256 $PythonComL  "CC5BA5439CFA435FC9BD442F6509EBDF83646DF0756093DFF6777775FD2246E6"
Assert-Sha256 $PyWinTypes  "C4DB872FF7D301186516882EA06422AEE29E1C11B44A4D382ADDD5B801207818"
Assert-Sha256 $Ujson       "F481A7AFB2DF7D834C2537D3DFA5CE1B22C0C40A83F4BD73602270A728951739"
Assert-Sha256 $ActiveDir   "EDFE01A38139D79A2EAC7B6F409B0495A447536CBB004318811D5CAF5842A556"
Assert-Sha256 $OpenSslZip  "644FEDF6FC567716EF25F4FC805E2AAAC5BB7D32D01349EAEB62802CD20AE81A"

$bootstrapRoot = Split-Path (Split-Path $BootstrapPython -Parent) -Parent
# For C:\Python27\python.exe, Split-Path -Parent once is the actual root.
$bootstrapRoot = Split-Path $BootstrapPython -Parent
$bootstrapLib  = Join-Path $bootstrapRoot "Lib"
$bootstrapDlls = Join-Path $bootstrapRoot "DLLs"
Assert-Dir $bootstrapLib
Assert-Dir $bootstrapDlls

# Prevent destructive/ambiguous output choices.
$repoFull = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
$outFull  = [IO.Path]::GetFullPath($Output).TrimEnd('\')
$kitFull  = [IO.Path]::GetFullPath($BuildKit).TrimEnd('\')

if ($outFull -eq $repoFull -or $outFull.StartsWith($repoFull + "\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must not be the WAPT repository or a child of it: $Output"
}
if ($outFull -eq $kitFull -or $outFull.StartsWith($kitFull + "\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must not be inside the controlled build-kit: $Output"
}

# Clear PYTHONPATH for every bootstrap operation.
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue

# Validate bootstrap interpreter.
$pyInfo = & $BootstrapPython -c "import sys,struct; print(sys.version.split()[0]); print(struct.calcsize('P')*8)"
if ($LASTEXITCODE -ne 0) { throw "Unable to run bootstrap Python." }
if ($pyInfo[0].Trim() -ne "2.7.18" -or $pyInfo[1].Trim() -ne "32") {
    throw "Bootstrap Python must be Python 2.7.18 x86. Got: $($pyInfo -join ' / ')"
}

if (Test-Path -LiteralPath $Output) {
    if (-not $Force) {
        throw "Output already exists: $Output. Use -Force to replace it."
    }
    Write-Step "Removing existing output"
    Remove-Item -LiteralPath $Output -Recurse -Force
}

# ---------------------------------------------------------------------------
# Create virtualenv
# ---------------------------------------------------------------------------

Write-Step "Creating isolated Python 2.7 runtime"

Invoke-Checked $BootstrapPython @("-m", "virtualenv", "--always-copy", $Output)

$RuntimePython  = Join-Path $Output "Scripts\python.exe"
$RuntimePythonW = Join-Path $Output "Scripts\pythonw.exe"
$RuntimePip     = Join-Path $Output "Scripts\pip.exe"

Assert-File $RuntimePython
Assert-File $RuntimePip

# ---------------------------------------------------------------------------
# Install controlled wheels
# ---------------------------------------------------------------------------

Write-Step "Installing generic requirements offline"

Invoke-Checked $RuntimePython @(
    "-m", "pip", "install",
    "--no-cache-dir", "--no-index", "--no-deps",
    "--find-links=$BuiltWheels",
    "--requirement", $ReqGeneric
)

# These transitive packages were explicitly required by the validated
# reconstructed runtime and are installed from the same controlled wheel set.
$ExplicitPackages = @(
    "monotonic==1.6",
    "dnspython==1.16.0",
    "smmap==3.0.5",
    "smmap2==3.0.1",
    "plumbum==1.7.2",
    "winkerberos==0.7.0",
    "pyasn1==0.5.1",
    "pywin32==228"
)

Write-Step "Installing explicit controlled transitive/native packages"
Invoke-Checked $RuntimePython (@(
    "-m", "pip", "install",
    "--no-cache-dir", "--no-index", "--no-deps",
    "--find-links=$BuiltWheels"
) + $ExplicitPackages)

# Install the Windows requirements exactly from the repository. ujson is
# injected from the controlled WAPT binary below, so exclude it from this pass.
$WindowsPackages = @(
    "pyad==0.5.20",
    "kerberos-sspi==0.2",
    "winshell==0.6",
    "winsys-3.x==0.5.2",
    "WMI==1.4.9"
)

Write-Step "Installing Windows requirement layer offline"
Invoke-Checked $RuntimePython (@(
    "-m", "pip", "install",
    "--no-cache-dir", "--no-index", "--no-deps",
    "--find-links=$BuiltWheels"
) + $WindowsPackages)

Write-Step "Checking Python package dependency consistency"
Invoke-Checked $RuntimePython @("-m", "pip", "check")

# ---------------------------------------------------------------------------
# Controlled WAPT-specific Python inputs and patches
# ---------------------------------------------------------------------------

$SitePackages = Join-Path $Output "Lib\site-packages"

Write-Step "Injecting controlled ujson and active_directory"
Copy-Checked $Ujson     (Join-Path $SitePackages "ujson.pyd") "F481A7AFB2DF7D834C2537D3DFA5CE1B22C0C40A83F4BD73602270A728951739"
Copy-Checked $ActiveDir (Join-Path $SitePackages "active_directory.py") "EDFE01A38139D79A2EAC7B6F409B0495A447536CBB004318811D5CAF5842A556"

Write-Step "Applying WAPT SocketIO and cryptography patches"

$SocketIoPatch = Join-Path $RepoRoot "utils\patch-socketio-client-2"
$CryptoPatch   = Join-Path $RepoRoot "utils\patch-cryptography"

Assert-Dir $SocketIoPatch
Assert-Dir $CryptoPatch

Copy-Item -LiteralPath (Join-Path $SocketIoPatch "__init__.py") `
    -Destination (Join-Path $SitePackages "socketIO_client\__init__.py") -Force
Copy-Item -LiteralPath (Join-Path $SocketIoPatch "transports.py") `
    -Destination (Join-Path $SitePackages "socketIO_client\transports.py") -Force

$CryptoX509 = Join-Path $SitePackages "cryptography\x509"
Assert-Dir $CryptoX509
Copy-Item -LiteralPath (Join-Path $CryptoPatch "__init__.py") `
    -Destination (Join-Path $CryptoX509 "__init__.py") -Force
Copy-Item -LiteralPath (Join-Path $CryptoPatch "verification.py") `
    -Destination (Join-Path $CryptoX509 "verification.py") -Force

# ---------------------------------------------------------------------------
# Embed CPython stdlib/DLLs and sever virtualenv base-prefix dependency
# ---------------------------------------------------------------------------

Write-Step "Embedding CPython 2.7 standard library"

# Merge, do not mirror/delete: site-packages already contains the controlled
# package layer assembled above.
& robocopy $bootstrapLib (Join-Path $Output "Lib") /E /R:0 /W:0 | Out-Host
if ($LASTEXITCODE -gt 7) { throw "robocopy Lib failed with code $LASTEXITCODE" }

Write-Step "Embedding CPython 2.7 native DLL directory"
& robocopy $bootstrapDlls (Join-Path $Output "DLLs") /E /R:0 /W:0 | Out-Host
if ($LASTEXITCODE -gt 7) { throw "robocopy DLLs failed with code $LASTEXITCODE" }

$OrigPrefix = Join-Path $Output "Lib\orig-prefix.txt"
if (Test-Path -LiteralPath $OrigPrefix) {
    Remove-Item -LiteralPath $OrigPrefix -Force
}

Write-Step "Installing controlled root runtime DLLs"

Copy-Checked $Python27Dll (Join-Path $Output "python27.dll") "8C81C84548CE191B11390EBAA71397D23662593B1C113AAA0392E40FF0F9307A"
Copy-Checked $PythonCom   (Join-Path $Output "pythoncom27.dll") "074F23F9710BBCF1447763829C0E3D16AFA5502EFC6F784077CF334F28CEFFB7"
Copy-Checked $PythonComL  (Join-Path $Output "pythoncomloader27.dll") "CC5BA5439CFA435FC9BD442F6509EBDF83646DF0756093DFF6777775FD2246E6"
Copy-Checked $PyWinTypes  (Join-Path $Output "pywintypes27.dll") "C4DB872FF7D301186516882EA06422AEE29E1C11B44A4D382ADDD5B801207818"

Copy-Item -LiteralPath $RuntimePython  -Destination (Join-Path $Output "waptpython.exe") -Force
Copy-Item -LiteralPath $RuntimePythonW -Destination (Join-Path $Output "waptpythonw.exe") -Force

# ---------------------------------------------------------------------------
# WAPT core source files
# ---------------------------------------------------------------------------

Write-Step "Copying WAPT core Python files"

$WaptCore = @(
    "waptutils.py",
    "waptcrypto.py",
    "common.py",
    "waptpackage.py",
    "wapt-get.py",
    "keyfinder.py",
    "setuphelpers.py",
    "setuphelpers_windows.py",
    "setuphelpers_linux.py",
    "setuphelpers_unix.py",
    "setuphelpers_macos.py",
    "windnsquery.py",
    "custom_zip.py"
)

foreach ($name in $WaptCore) {
    $src = Join-Path $RepoRoot $name
    Assert-File $src
    Copy-Item -LiteralPath $src -Destination (Join-Path $Output $name) -Force
}

# ---------------------------------------------------------------------------
# External WAPT OpenSSL baseline
# ---------------------------------------------------------------------------

Write-Step "Adding controlled external WAPT OpenSSL baseline"

$sslTemp = Join-Path ([IO.Path]::GetTempPath()) ("wapt-openssl-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $sslTemp | Out-Null
try {
    Expand-Archive -LiteralPath $OpenSslZip -DestinationPath $sslTemp

    Copy-Checked (Join-Path $sslTemp "openssl.exe") `
        (Join-Path $Output "openssl.exe") `
        "6063E160E812F3D57B67B77581E30F110FDFC708F763BB2FCC82FA9CAAC816A3"

    Copy-Checked (Join-Path $sslTemp "libeay32.dll") `
        (Join-Path $Output "libeay32.dll") `
        "5264A4A478383F501961F2BD9BEB1F77A43A487B76090561BBA2CBFE951E5305"

    Copy-Checked (Join-Path $sslTemp "ssleay32.dll") `
        (Join-Path $Output "ssleay32.dll") `
        "0A4031AB00664CC5E202C8731798800F0475EF76800122CEBD71D249655D725F"
}
finally {
    Remove-Item -LiteralPath $sslTemp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Acceptance tests
# ---------------------------------------------------------------------------

Write-Step "Running autonomous runtime acceptance tests"

Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue

$TestScript = @'
import sys
import ctypes

assert sys.version.startswith("2.7.18")
assert sys.maxsize == 2147483647

bad = [p for p in sys.path if p and p.lower().startswith(r"c:\python27")]
assert not bad, "System Python leaked into sys.path: %r" % bad

k32 = ctypes.windll.kernel32
h = k32.GetModuleHandleA("python27.dll")
assert h
buf = ctypes.create_string_buffer(1024)
k32.GetModuleFileNameA(h, buf, len(buf))
loaded = buf.value.lower()
expected = (sys.prefix + r"\python27.dll").lower()
assert loaded == expected, "Wrong python27.dll loaded: %s (expected %s)" % (loaded, expected)

import os, json, ssl, hashlib, sqlite3, ctypes
import pythoncom, pywintypes, win32api
import ujson
import active_directory
import cryptography.x509.verification
import waptutils
import waptcrypto
import waptpackage
import setuphelpers
import common

assert waptutils.__version__ == "1.8.3"

print("Python:", sys.version.split()[0])
print("Executable:", sys.executable)
print("Prefix:", sys.prefix)
print("Loaded python27.dll:", buf.value)
print("pywin32: OK")
print("WAPT core: OK")
print("WAPT 1.8.3 AUTONOMOUS RUNTIME: PASS")
'@

$TestFile = Join-Path $env:TEMP ("wapt-runtime-test-" + [Guid]::NewGuid().ToString("N") + ".py")
[IO.File]::WriteAllText($TestFile, $TestScript, [Text.Encoding]::ASCII)
try {
    Push-Location $env:TEMP
    try {
        Invoke-Checked (Join-Path $Output "waptpython.exe") @($TestFile)
        Invoke-Checked (Join-Path $Output "waptpython.exe") @((Join-Path $Output "wapt-get.py"), "--help")
        Invoke-Checked (Join-Path $Output "openssl.exe") @("version")
    }
    finally {
        Pop-Location
    }
}
finally {
    Remove-Item -LiteralPath $TestFile -Force -ErrorAction SilentlyContinue
}

Write-Step "SUCCESS"
Write-Host "Autonomous WAPT 1.8.3 runtime assembled at:"
Write-Host "  $Output"
Write-Host ""
Write-Host "This script does not yet build Lazarus projects, populate the full product tree,"
Write-Host "compile the Inno Setup installer, or sign release artifacts."
