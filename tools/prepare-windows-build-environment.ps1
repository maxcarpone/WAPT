[CmdletBinding()]
param(
    [string]$BuildKit = 'C:\wapt-build-kit',
    [string]$PythonRoot = 'C:\Python27',
    [string]$LazarusRoot = 'C:\lazarus'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Assert-FileHash {
    param(
        [string]$Path,
        [string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Controlled input not found: $Path"
    }

    $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash

    if ($Actual -ne $ExpectedSha256) {
        throw @"
SHA256 mismatch:
  File:     $Path
  Expected: $ExpectedSha256
  Actual:   $Actual
"@
    }

    Write-Host "[PASS] SHA256: $Path"
}

function Invoke-CheckedProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList
    )

    $Process = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -Wait `
        -PassThru

    if ($Process.ExitCode -ne 0) {
        throw "Command failed with exit code $($Process.ExitCode): $FilePath"
    }
}

$GitInstaller = Join-Path $BuildKit 'git\Git-2.55.0.5-64-bit.exe'
$PythonInstaller = Join-Path $BuildKit 'python\python-2.7.18-x86.msi'
$VirtualenvWheel = Join-Path $BuildKit 'python\virtualenv-15.1.0-py2.py3-none-any.whl'
$LazarusInstaller = Join-Path $BuildKit 'lazarus\lazarus-1.8.2-fpc-3.0.4-win32.exe'

$PythonExe = Join-Path $PythonRoot 'python.exe'
$LazbuildExe = Join-Path $LazarusRoot 'lazbuild.exe'
$FpcExe = Join-Path $LazarusRoot 'fpc\3.0.4\bin\i386-win32\fpc.exe'

Write-Step 'Validating controlled bootstrap inputs'

Assert-FileHash $GitInstaller `
    'D065A4E23C3D9A6B5073D609B5BE0830227EC3CA053C083BA385061DDFAF94C6'

Assert-FileHash $PythonInstaller `
    'D901802E90026E9BAD76B8A81F8DD7E43C7D7E8269D9281C9E9DF7A9C40480A9'

Assert-FileHash $VirtualenvWheel `
    '39D88B533B422825D644087A21E78C45CF5AF0EF7A99A1FC9FBB7B481E5C85B0'

Assert-FileHash $LazarusInstaller `
    'B91517C673453F5AA355FFB3952E040433A8CDBBC5239BE72C869B60131B4166'

Write-Step 'Checking Git 2.55.0.windows.5'

$GitOk = $false

try {
    $GitVersion = (& git --version 2>$null).Trim()
    $GitOk = ($GitVersion -eq 'git version 2.55.0.windows.5')
} catch {
    $GitOk = $false
}

if (-not $GitOk) {
    Write-Host 'Installing controlled Git...'

    Invoke-CheckedProcess `
        $GitInstaller `
        @('/VERYSILENT','/NORESTART')

    $env:Path = 'C:\Program Files\Git\cmd;' + $env:Path
}

$GitVersion = (& git --version).Trim()

if ($GitVersion -ne 'git version 2.55.0.windows.5') {
    throw "Unexpected Git version: $GitVersion"
}

Write-Host "[PASS] $GitVersion"

Write-Step 'Checking CPython 2.7.18 x86'

$PythonOk = $false

if (Test-Path -LiteralPath $PythonExe -PathType Leaf) {
    $PythonVersion = (& $PythonExe -c "import platform,sys; print(sys.version_info[:3]); print(platform.architecture()[0])")

    if (($PythonVersion -contains '(2, 7, 18)') -and
        ($PythonVersion -contains '32bit')) {
        $PythonOk = $true
    }
}

if (-not $PythonOk) {
    Write-Host 'Installing controlled CPython 2.7.18 x86...'

    Invoke-CheckedProcess `
        'msiexec.exe' `
        @(
            '/i',
            $PythonInstaller,
            '/qn',
            '/norestart',
            "TARGETDIR=$PythonRoot"
        )
}

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw "Python executable not found after installation: $PythonExe"
}

$PythonCheck = (& $PythonExe -c "import platform,sys; print('%d.%d.%d' % sys.version_info[:3]); print(platform.architecture()[0])")

if (($PythonCheck[0] -ne '2.7.18') -or
    ($PythonCheck[1] -ne '32bit')) {
    throw "Unexpected bootstrap Python: $($PythonCheck -join ' / ')"
}

Write-Host '[PASS] CPython 2.7.18 x86'

Write-Step 'Checking virtualenv 15.1.0'

$VirtualenvOk = $false

try {
    $VirtualenvVersion = (& $PythonExe -m virtualenv --version 2>$null).Trim()
    $VirtualenvOk = ($VirtualenvVersion -eq '15.1.0')
} catch {
    $VirtualenvOk = $false
}

if (-not $VirtualenvOk) {
    Write-Host 'Installing controlled virtualenv 15.1.0 offline...'

    & $PythonExe -m pip install `
        --no-index `
        --no-deps `
        $VirtualenvWheel

    if ($LASTEXITCODE -ne 0) {
        throw "Offline virtualenv installation failed."
    }
}

$VirtualenvVersion = (& $PythonExe -m virtualenv --version).Trim()

if ($VirtualenvVersion -ne '15.1.0') {
    throw "Unexpected virtualenv version: $VirtualenvVersion"
}

Write-Host '[PASS] virtualenv 15.1.0'

Write-Step 'Checking Lazarus 1.8.2 / FPC 3.0.4'

$LazarusOk = $false

if ((Test-Path -LiteralPath $LazbuildExe -PathType Leaf) -and
    (Test-Path -LiteralPath $FpcExe -PathType Leaf)) {

    $LazarusVersion = (& $LazbuildExe --version).Trim()
    $FpcVersion = (& $FpcExe -iV).Trim()

    if (($LazarusVersion -eq '1.8.2') -and
        ($FpcVersion -eq '3.0.4')) {
        $LazarusOk = $true
    }
}

if (-not $LazarusOk) {
    Write-Host 'Installing controlled Lazarus 1.8.2 / FPC 3.0.4...'

    Invoke-CheckedProcess `
        $LazarusInstaller `
        @(
            '/VERYSILENT',
            '/NORESTART',
            "/DIR=$LazarusRoot"
        )
}

$LazarusVersion = (& $LazbuildExe --version).Trim()
$FpcVersion = (& $FpcExe -iV).Trim()

if ($LazarusVersion -ne '1.8.2') {
    throw "Unexpected Lazarus version: $LazarusVersion"
}

if ($FpcVersion -ne '3.0.4') {
    throw "Unexpected FPC version: $FpcVersion"
}

Write-Host '[PASS] Lazarus 1.8.2'
Write-Host '[PASS] FPC 3.0.4'

Write-Step 'Windows build environment ready'

Write-Host ''
Write-Host '[PASS] Controlled Windows build prerequisites validated.'
Write-Host ''
Write-Host 'Git:             2.55.0.windows.5'
Write-Host 'Python:          2.7.18 x86'
Write-Host 'virtualenv:      15.1.0'
Write-Host 'Lazarus:         1.8.2'
Write-Host 'FPC:             3.0.4'
Write-Host 'VCForPython27:   not required'
Write-Host 'Global Inno:     not required'
