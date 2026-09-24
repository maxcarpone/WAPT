[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$BuildKit = 'C:\wapt-build-kit',
    [string]$Runtime = 'C:\wapt-runtime-1.8.3',
    [string]$Output = 'C:\wapt-product-1.8.3',
    [string]$Worktree = 'C:\wapt-build-worktree-auto',
    [string]$Lazarus = 'C:\lazarus',
    [string]$LazarusPcp = 'C:\wapt-build-lazarus-pcp-auto',
    [switch]$Force
)

if (-not $SourceRoot) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}

$ErrorActionPreference = 'Stop'

function Assert-File {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Sha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file missing: $Path"
    }

    if ($Sha256) {
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($actual -ne $Sha256) {
            throw "SHA256 mismatch: $Path`nExpected: $Sha256`nActual:   $actual"
        }
    }
}

function Assert-Directory {
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Required directory missing: $Path"
    }
}

function Assert-SafeDisposablePath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$ProtectedPaths
    )

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')

    if ([IO.Path]::GetPathRoot($fullPath).TrimEnd('\') -eq $fullPath) {
        throw "Refusing to use drive root as disposable path: $fullPath"
    }

    foreach ($protected in $ProtectedPaths) {
        $protectedFull = [IO.Path]::GetFullPath($protected).TrimEnd('\')

        $fullPrefix = $fullPath + '\'
        $protectedPrefix = $protectedFull + '\'

        if (
            $fullPath -ieq $protectedFull -or
            $fullPrefix.StartsWith($protectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $protectedPrefix.StartsWith($fullPrefix, [StringComparison]::OrdinalIgnoreCase)
        ) {
            throw "Disposable path overlaps protected path: $fullPath <-> $protectedFull"
        }
    }
}

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$BuildKit   = [IO.Path]::GetFullPath($BuildKit)
$Runtime    = [IO.Path]::GetFullPath($Runtime)
$Output     = [IO.Path]::GetFullPath($Output)
$Worktree   = [IO.Path]::GetFullPath($Worktree)
$Lazarus    = [IO.Path]::GetFullPath($Lazarus)
$LazarusPcp = [IO.Path]::GetFullPath($LazarusPcp)

$ProtectedPaths = @(
    $SourceRoot,
    $BuildKit,
    $Runtime,
    $Lazarus
)

Assert-SafeDisposablePath -Path $Output     -ProtectedPaths $ProtectedPaths
Assert-SafeDisposablePath -Path $Worktree   -ProtectedPaths $ProtectedPaths
Assert-SafeDisposablePath -Path $LazarusPcp -ProtectedPaths $ProtectedPaths

Assert-SafeDisposablePath -Path $Output `
    -ProtectedPaths @($Worktree, $LazarusPcp)

Assert-SafeDisposablePath -Path $Worktree `
    -ProtectedPaths @($Output, $LazarusPcp)

Assert-SafeDisposablePath -Path $LazarusPcp `
    -ProtectedPaths @($Output, $Worktree)

Write-Host "WAPT Windows product assembly"
Write-Host "Source : $SourceRoot"
Write-Host "Kit    : $BuildKit"
Write-Host "Runtime: $Runtime"
Write-Host "Output : $Output"
Write-Host "Worktree: $Worktree"
Write-Host "Lazarus : $Lazarus"
Write-Host "PCP     : $LazarusPcp"
Write-Host ""

# ----------------------------------------------------------------------
# Controlled inputs
# ----------------------------------------------------------------------

$Vc90 = Join-Path $BuildKit 'runtime\vc90-crt'
$Tools = Join-Path $BuildKit 'runtime\tools'
$Nssm = Join-Path $BuildKit 'runtime\nssm'
$InnoInstaller = Join-Path $BuildKit 'inno-setup\innosetup-5.6.0-unicode.exe'

Assert-Directory $SourceRoot
Assert-Directory $BuildKit
Assert-Directory $Runtime
Assert-File (Join-Path $Lazarus 'lazbuild.exe')
Assert-File (Join-Path $Runtime 'waptpython.exe')

Assert-File (Join-Path $Vc90 'msvcr90.dll') `
    '8E7FE1A1F3550C479FFD86A77BC9D10686D47F8727025BB891D8F4F0259354C8'

Assert-File (Join-Path $Vc90 'msvcp90.dll') `
    '06918CF99AD26CD6CF106881C0D5BDB212DC0BAC4549805C9F5906E3D03D152C'

Assert-File (Join-Path $Vc90 'msvcm90.dll') `
    '7A74DA389FBD10A710C294C2E914DC6F18E05F028F07958A2FA53AC44F0E4B90'

Assert-File (Join-Path $Vc90 'Microsoft.VC90.CRT.manifest') `
    '0C838C4262F99F27495A7C2A1BF4EC8F482D1C9BC2493C3C19B9360F1A06B8EB'

Assert-File (Join-Path $Tools 'dmidecode.exe') `
    '7E14292571834665F0788C1BDE495421F704FAB74679127CBE35AF65714587F2'

Assert-File (Join-Path $Nssm 'win32\nssm.exe') `
    'BCE355F89B95D9F7C7441563D03A6CE6CD429DB865920F66561C0D90D1E0E285'

Assert-File (Join-Path $Nssm 'win64\nssm.exe') `
    '2900F26D2ED74F4D5DB77CBCCBD4F2185FCCE2625A1BE724120984AC2418989B'

Assert-File $InnoInstaller `
    '84A97B5820F83E7EB7258B69CC857C4F446DFB5C7C337C35E05A0CC304729346'

$InnoRootFiles = @(
    'Default.isl',
    'isbunzip.dll',
    'isbzip.dll',
    'ISCC.exe',
    'ISCmplr.dll',
    'islzma.dll',
    'islzma32.exe',
    'islzma64.exe',
    'ISPP.dll',
    'ISPPBuiltins.iss',
    'isscint.dll',
    'isunzlib.dll',
    'iszlib.dll',
    'license.txt',
    'Setup.e32',
    'SetupLdr.e32',
    'WizModernImage-IS.bmp',
    'WizModernImage.bmp',
    'WizModernSmallImage-IS.bmp',
    'WizModernSmallImage.bmp'
)

# Runtime must be autonomous and already validated.
Assert-File (Join-Path $Runtime 'waptpython.exe')
Assert-File (Join-Path $Runtime 'waptpythonw.exe')
Assert-File (Join-Path $Runtime 'python27.dll')
Assert-File (Join-Path $Runtime 'pythoncom27.dll')
Assert-File (Join-Path $Runtime 'pythoncomloader27.dll')
Assert-File (Join-Path $Runtime 'pywintypes27.dll')
Assert-File (Join-Path $Runtime 'libeay32.dll')
Assert-File (Join-Path $Runtime 'ssleay32.dll')
Assert-File (Join-Path $Runtime 'openssl.exe')
Assert-Directory (Join-Path $Runtime 'DLLs')
Assert-Directory (Join-Path $Runtime 'Lib')
Assert-Directory (Join-Path $Runtime 'Scripts')

Assert-Directory (Join-Path $Runtime 'libs')

$runtimeLibFiles = Get-ChildItem -LiteralPath (Join-Path $Runtime 'libs') -File
if ($runtimeLibFiles.Count -ne 19) {
    throw "Invalid runtime libs directory: expected 19 files, found $($runtimeLibFiles.Count)"
}

# Required Git-controlled product sources.
Assert-Directory (Join-Path $SourceRoot 'waptservice')
Assert-Directory (Join-Path $SourceRoot 'templates')
Assert-Directory (Join-Path $SourceRoot 'languages')
Assert-Directory (Join-Path $SourceRoot 'waptupgrade')
Assert-Directory (Join-Path $SourceRoot 'waptsetup')

Assert-File (Join-Path $SourceRoot 'COPYING.txt')
Assert-File (Join-Path $SourceRoot 'cache\icons\unknown.png')
Assert-File (Join-Path $SourceRoot 'waptsetup\waptsetup.iss')
Assert-File (Join-Path $SourceRoot 'waptsetup\common.iss')
Assert-File (Join-Path $SourceRoot 'waptsetup\wapt.iss')
Assert-File (Join-Path $SourceRoot 'waptsetup\services.iss')

# Git-controlled root resources required by the installer.
Assert-File (Join-Path $SourceRoot 'tranquilit.bmp')
Assert-File (Join-Path $SourceRoot 'wapt.ico')
Assert-File (Join-Path $SourceRoot 'waptdevutils.py')
Assert-File (Join-Path $SourceRoot 'create_version_full.py')

# Additional Git-controlled Inno Setup sources.
Assert-File (Join-Path $SourceRoot 'waptsetup\waptagent.iss')
Assert-File (Join-Path $SourceRoot 'waptsetup\waptserversetup.iss')
Assert-File (Join-Path $SourceRoot 'waptsetup\waptstarter.iss')

# Git-controlled installer languages.
Assert-File (Join-Path $SourceRoot 'waptsetup\innosetup\Languages\French.isl')
Assert-File (Join-Path $SourceRoot 'waptsetup\innosetup\Languages\German.isl')
Assert-File (Join-Path $SourceRoot 'waptsetup\innosetup\Languages\french.lng')

Write-Host ""
Write-Host "[PASS] All controlled product-assembly inputs are present and validated."

# ----------------------------------------------------------------------
# Resolve exact Git source revision
# ----------------------------------------------------------------------

Write-Host "Resolving Git source revision..."

$SourceCommit = (& git -C $SourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $SourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Unable to resolve Git HEAD from $SourceRoot"
}

$BuildNumber = (& git -C $SourceRoot rev-list --count HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $BuildNumber -notmatch '^\d+$') {
    throw "Unable to determine natural Git build number"
}

$BuildBranch = "build/windows-1.8.3-$BuildNumber-auto"

Write-Host "Source commit : $SourceCommit"
Write-Host "Build number  : $BuildNumber"
Write-Host "Build branch  : $BuildBranch"

# ----------------------------------------------------------------------
# Prepare isolated Git worktree
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Preparing isolated Git worktree..."

# Remove a previous disposable worktree if explicitly allowed.
if (Test-Path -LiteralPath $Worktree) {
    if (-not $Force) {
        throw "Worktree directory already exists: $Worktree. Use -Force to replace it."
    }

    # First try the normal Git-aware removal.
    & git -C $SourceRoot worktree remove --force $Worktree 2>$null

    if ($LASTEXITCODE -ne 0) {
        # The directory may be a stale/unregistered disposable worktree.
        # Never delete it unless it still identifies itself as a Git worktree
        # belonging to this repository.
        $staleCommonDir = (& git -C $Worktree rev-parse --git-common-dir 2>$null)

        if ($LASTEXITCODE -ne 0 -or -not $staleCommonDir) {
            throw "Existing path is not a recognized Git worktree; refusing recursive deletion: $Worktree"
        }

        $expectedCommonDir = (& git -C $SourceRoot rev-parse --git-common-dir).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to resolve source repository common Git directory"
        }

        $actualCommonDir = $staleCommonDir.Trim()

        if (-not [IO.Path]::IsPathRooted($expectedCommonDir)) {
            $expectedCommonDir = Join-Path $SourceRoot $expectedCommonDir
        }

        if (-not [IO.Path]::IsPathRooted($actualCommonDir)) {
            $actualCommonDir = Join-Path $Worktree $actualCommonDir
        }

        $expectedCommonDir = [IO.Path]::GetFullPath($expectedCommonDir).TrimEnd('\')
        $actualCommonDir   = [IO.Path]::GetFullPath($actualCommonDir).TrimEnd('\')

        if ($actualCommonDir -ine $expectedCommonDir) {
            throw "Existing path belongs to another Git repository; refusing deletion: $Worktree"
        }

        Remove-Item -LiteralPath $Worktree -Recurse -Force
        & git -C $SourceRoot worktree prune
    }
}

# Remove a stale local build branch from a previous run.
$existingBranch = & git -C $SourceRoot branch --list $BuildBranch
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect local Git build branch"
}

if ($existingBranch) {
    if (-not $Force) {
        throw "Local build branch already exists: $BuildBranch. Use -Force to replace it."
    }

    & git -C $SourceRoot branch -D $BuildBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to remove stale local build branch: $BuildBranch"
    }
}

& git -C $SourceRoot worktree add -b $BuildBranch $Worktree $SourceCommit
if ($LASTEXITCODE -ne 0) {
    throw "Unable to create Git worktree: $Worktree"
}

$WorktreeCommit = (& git -C $Worktree rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $WorktreeCommit -ne $SourceCommit) {
    throw "Worktree HEAD mismatch. Expected $SourceCommit, got $WorktreeCommit"
}

$WorktreeBranch = (& git -C $Worktree branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $WorktreeBranch -ne $BuildBranch) {
    throw "Worktree branch mismatch. Expected $BuildBranch, got $WorktreeBranch"
}

Write-Host "Worktree commit : $WorktreeCommit"
Write-Host "Worktree branch : $WorktreeBranch"
Write-Host "[PASS] Isolated Git worktree created."

# ----------------------------------------------------------------------
# Synchronize submodule configuration
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Synchronizing Git submodule configuration..."

& git -C $Worktree submodule sync --recursive
if ($LASTEXITCODE -ne 0) {
    throw "Git submodule sync failed"
}

Write-Host "[PASS] Git submodule configuration synchronized."

# ----------------------------------------------------------------------
# Initialize Community submodules only
# ----------------------------------------------------------------------

$CommunitySubmodules = @(
    'submodules\pltis_bgrabitmap',
    'submodules\pltis_bgracontrols',
    'submodules\pltis_bgracontrolsfx',
    'submodules\pltis_dcpcrypt',
    'submodules\pltis_indy',
    'submodules\pltis_lazarus-exception-logger',
    'submodules\pltis_lclextensions',
    'submodules\pltis_luipack',
    'submodules\pltis_python4delphi',
    'submodules\pltis_sogrid',
    'submodules\pltis_superobject',
    'submodules\pltis_synapse',
    'submodules\pltis_utils',
    'submodules\pltis_virtualtrees',
    'submodules\pltis_virtualtreesextra',
    'submodules\pltis_visualcontrols'
)

Write-Host ""
Write-Host "Initializing 16 Community submodules..."

foreach ($submodule in $CommunitySubmodules) {
    & git -C $Worktree submodule update --init -- $submodule

    if ($LASTEXITCODE -ne 0) {
        throw "Git submodule update failed: $submodule"
    }
}

Write-Host "[PASS] Community submodules initialized: 16/16"

Write-Host ""
Write-Host "Verifying Community submodule gitlinks..."

foreach ($submodule in $CommunitySubmodules) {
    $gitPath = $submodule -replace '\\', '/'

    $expectedCommit = (& git -C $Worktree rev-parse "HEAD:$gitPath").Trim()
    if ($LASTEXITCODE -ne 0 -or $expectedCommit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "Unable to resolve expected gitlink: $submodule"
    }

    $actualCommit = (& git -C (Join-Path $Worktree $submodule) rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualCommit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "Unable to resolve submodule HEAD: $submodule"
    }

    if ($actualCommit -ne $expectedCommit) {
        throw "Submodule gitlink mismatch: $submodule`nExpected: $expectedCommit`nActual:   $actualCommit"
    }
}

Write-Host "[PASS] Community submodule gitlinks verified: 16/16"

# ----------------------------------------------------------------------
# Prepare isolated Lazarus primary config path
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Preparing isolated Lazarus PCP..."

if (Test-Path -LiteralPath $LazarusPcp) {
    if (-not $Force) {
        throw "Lazarus PCP already exists: $LazarusPcp. Use -Force to replace it."
    }

    Remove-Item -LiteralPath $LazarusPcp -Recurse -Force
}

New-Item -ItemType Directory -Path $LazarusPcp | Out-Null

if (-not (Test-Path -LiteralPath $LazarusPcp -PathType Container)) {
    throw "Unable to create Lazarus PCP: $LazarusPcp"
}

Write-Host "[PASS] Isolated Lazarus PCP created."

$LazarusPackages = @(
    'submodules\pltis_dcpcrypt\dcpcrypt_laz.lpk',
    'submodules\pltis_indy\Lib\indylaz.lpk',
    'submodules\pltis_utils\pltis_utils.lpk',
    'submodules\pltis_superobject\pltis_superobject.lpk',
    'submodules\pltis_synapse\laz_synapse.lpk',
    'submodules\pltis_python4delphi\Packages\FPC\p4dlaz.lpk',
    'submodules\pltis_lazarus-exception-logger\ExceptionLogger.lpk',
    'submodules\pltis_lclextensions\lclextensions_package.lpk',
    'submodules\pltis_virtualtrees\pltis_virtualtrees.lpk',
    'submodules\pltis_virtualtreesextra\pltis_virtualtreesextra.lpk',
    'submodules\pltis_sogrid\pltis_sogrid.lpk',
    'submodules\pltis_bgrabitmap\bgrabitmap\bgrabitmappack.lpk',
    'submodules\pltis_bgracontrols\bgracontrols.lpk',
    'submodules\pltis_bgracontrolsfx\bgracontrolsfx.lpk',
    'submodules\pltis_luipack\luicomponents\luicomponents.lpk',
    'submodules\pltis_luipack\luicontrols\luicontrols.lpk',
    'wapt-get\pltis_wapt.lpk'
)

if ($LazarusPackages.Count -ne 17) {
    throw "Unexpected Lazarus package count: expected 17, found $($LazarusPackages.Count)"
}

foreach ($package in $LazarusPackages) {
    Assert-File (Join-Path $Worktree $package)
}

Write-Host "[PASS] Lazarus package files validated: 17/17"

# ----------------------------------------------------------------------
# Register Lazarus packages in isolated PCP
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Registering Lazarus packages..."

$LazbuildExe = Join-Path $Lazarus 'lazbuild.exe'

foreach ($package in $LazarusPackages) {
    $packagePath = Join-Path $Worktree $package

    & $LazbuildExe `
        "--primary-config-path=$LazarusPcp" `
        "--lazarusdir=$Lazarus" `
        "--compiler=ppc386" `
        '--add-package-link' `
        "$packagePath"

    if ($LASTEXITCODE -ne 0) {
        throw "Lazarus package registration failed: $package"
    }
}

Write-Host "[PASS] Lazarus packages registered: 17/17"

# ----------------------------------------------------------------------
# Lazarus Community build targets
# ----------------------------------------------------------------------

$LazarusProjects = @(
    'wapt-get\waptget.lpi',
    'wapt-get\WaptGuiHelper.lpi',
    'waptdeploy\waptdeploy.lpi',
    'wapttray\wapttray.lpi',
    'waptconsole\waptconsole.lpi',
    'waptexit\waptexit.lpi',
    'waptself\waptself.lpi',
    'waptmessage\waptmessage.lpi',
    'waptsetup\waptsetuputil\waptsetuputil.lpi'
)

if ($LazarusProjects.Count -ne 9) {
    throw "Unexpected Lazarus project count: expected 9, found $($LazarusProjects.Count)"
}

foreach ($project in $LazarusProjects) {
    Assert-File (Join-Path $Worktree $project)
}

Write-Host "[PASS] Lazarus project files validated: 9/9"

# ----------------------------------------------------------------------
# Build Lazarus Community targets
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Building Lazarus Community targets..."

$WaptPython = Join-Path $Runtime 'waptpython.exe'
$LazbuildPy = Join-Path $Worktree 'lazbuild.py'

Assert-File $WaptPython
Assert-File $LazbuildPy

foreach ($project in $LazarusProjects) {
    $projectPath = Join-Path $Worktree $project

    & $WaptPython $LazbuildPy `
        '-l' $LazbuildExe `
        '-p' $LazarusPcp `
        '-e' 'community' `
        $projectPath

    if ($LASTEXITCODE -ne 0) {
        throw "Lazarus build failed: $project"
    }
}

Write-Host "[PASS] Lazarus Community builds completed: 9/9"

# ----------------------------------------------------------------------
# Validate Lazarus build artifacts
# ----------------------------------------------------------------------

$LazarusArtifacts = @(
    'wapt-get.exe',
    'waptguihelper.pyd',
    'waptdeploy.exe',
    'wapttray.exe',
    'waptconsole.exe',
    'waptexit.exe',
    'waptself.exe',
    'waptmessage.exe',
    'waptsetuputil.dll'
)

if ($LazarusArtifacts.Count -ne 9) {
    throw "Unexpected Lazarus artifact count: expected 9, found $($LazarusArtifacts.Count)"
}

foreach ($artifact in $LazarusArtifacts) {
    Assert-File (Join-Path $Worktree $artifact)
}

Write-Host "[PASS] Lazarus build artifacts validated: 9/9"

Write-Host ""
Write-Host "Verifying Lazarus artifact metadata..."

$ExpectedFileVersion = "1.8.3.$BuildNumber"
$ExpectedProductVersion = '1.8.3'
$ExpectedProductName = 'WAPT Community Edition'

foreach ($artifact in $LazarusArtifacts) {
    $artifactPath = Join-Path $Worktree $artifact
    $versionInfo = (Get-Item -LiteralPath $artifactPath).VersionInfo

    if ($versionInfo.FileVersion -ne $ExpectedFileVersion) {
        throw "FileVersion mismatch: $artifact`nExpected: $ExpectedFileVersion`nActual:   $($versionInfo.FileVersion)"
    }

    if ($versionInfo.ProductVersion -ne $ExpectedProductVersion) {
        throw "ProductVersion mismatch: $artifact`nExpected: $ExpectedProductVersion`nActual:   $($versionInfo.ProductVersion)"
    }

    if ($versionInfo.ProductName -ne $ExpectedProductName) {
        throw "ProductName mismatch: $artifact`nExpected: $ExpectedProductName`nActual:   $($versionInfo.ProductName)"
    }
}

Write-Host "[PASS] Lazarus artifact metadata validated: 9/9"
Write-Host "       FileVersion    : $ExpectedFileVersion"
Write-Host "       ProductVersion : $ExpectedProductVersion"
Write-Host "       ProductName    : $ExpectedProductName"

# ----------------------------------------------------------------------
# Use exact worktree revision for all Git-controlled product content
# ----------------------------------------------------------------------

$ProductSource = $Worktree

if ((& git -C $ProductSource rev-parse HEAD).Trim() -ne $SourceCommit) {
    throw "Product source is not at expected commit: $SourceCommit"
}

Write-Host "[PASS] Product Git source locked to isolated worktree: $SourceCommit"

# ----------------------------------------------------------------------
# Assemble product tree
# ----------------------------------------------------------------------

if (Test-Path -LiteralPath $Output) {
    if (-not $Force) {
        throw "Output directory already exists: $Output. Use -Force to replace it."
    }

    Write-Host "Removing existing product tree..."
    Remove-Item -LiteralPath $Output -Recurse -Force
}

Write-Host ""
Write-Host "Creating product tree: $Output"

New-Item -ItemType Directory -Path $Output | Out-Null

# Start from the validated autonomous Python runtime.
Write-Host "Copying autonomous Python runtime..."
Copy-Item -Path (Join-Path $Runtime '*') `
          -Destination $Output `
          -Recurse -Force

# Controlled external binaries.
Write-Host "Installing controlled external binaries..."

Copy-Item (Join-Path $Vc90 'msvcr90.dll') $Output
Copy-Item (Join-Path $Vc90 'msvcp90.dll') $Output
Copy-Item (Join-Path $Vc90 'msvcm90.dll') $Output
Copy-Item (Join-Path $Vc90 'Microsoft.VC90.CRT.manifest') $Output

Copy-Item (Join-Path $Tools 'dmidecode.exe') $Output

# Product source trees required by Inno Setup.
Write-Host "Copying Git-controlled product trees..."

foreach ($dir in @(
    'templates',
    'languages',
    'waptupgrade',
    'waptservice'
)) {
    Copy-Item `
        -LiteralPath (Join-Path $ProductSource $dir) `
        -Destination $Output `
        -Recurse -Force
}

# Replace NSSM with the controlled build-kit copies.
Write-Host "Installing controlled NSSM binaries..."

$Nssm32Target = Join-Path $Output 'waptservice\win32'
$Nssm64Target = Join-Path $Output 'waptservice\win64'

New-Item -ItemType Directory -Path $Nssm32Target -Force | Out-Null
New-Item -ItemType Directory -Path $Nssm64Target -Force | Out-Null

Copy-Item (Join-Path $Nssm 'win32\nssm.exe') `
          (Join-Path $Nssm32Target 'nssm.exe') -Force

Copy-Item (Join-Path $Nssm 'win64\nssm.exe') `
          (Join-Path $Nssm64Target 'nssm.exe') -Force

# Individual Git-controlled files required by wapt.iss.
foreach ($file in @(
    'COPYING.txt',
    'tranquilit.bmp',
    'wapt.ico',
    'waptdevutils.py',
    'cache\icons\unknown.png',
    'wapt-get.exe.manifest',
    'waptconsole.exe.manifest',
    'wapt-scanpackages.bat',
    'wapt-scanpackages.py',
    'wapt-signpackages.bat',
    'wapt-signpackages.py',
    'runwaptservice.bat',
    'wapt.psproj',
    'devwapt.bat',
    'waptpyscripter.bat',
    'wapt-get.ini.tmpl'
)) {
    $src = Join-Path $ProductSource $file
    Assert-File $src

    $dst = Join-Path $Output $file
    $dstDir = Split-Path -Parent $dst

    if ($dstDir -and -not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
}

# ----------------------------------------------------------------------
# Git-controlled Inno Setup scripts
# ----------------------------------------------------------------------

Write-Host "Copying Git-controlled Inno Setup scripts..."

$WaptSetupTarget = Join-Path $Output 'waptsetup'
New-Item -ItemType Directory -Path $WaptSetupTarget -Force | Out-Null

$InnoScripts = @(
    'common.iss',
    'services.iss',
    'wapt.iss',
    'waptagent.iss',
    'waptserversetup.iss',
    'waptsetup.iss',
    'waptstarter.iss'
)

foreach ($file in $InnoScripts) {
    $src = Join-Path $ProductSource "waptsetup\$file"
    Assert-File $src
    Copy-Item -LiteralPath $src -Destination (Join-Path $WaptSetupTarget $file) -Force
}

$innoScriptFiles = Get-ChildItem -LiteralPath $WaptSetupTarget -File -Filter '*.iss'
if ($innoScriptFiles.Count -ne 7) {
    throw "Unexpected Inno script count: expected 7, found $($innoScriptFiles.Count)"
}

Write-Host "Git-controlled Inno scripts: 7/7 PASS"

# ----------------------------------------------------------------------
# Reconstruct controlled Inno Setup tree
# ----------------------------------------------------------------------

Write-Host "Reconstructing controlled Inno Setup 5.6.0 tree..."

$InnoTemp = Join-Path $env:TEMP (
    'wapt-innosetup-5.6.0-' + [Guid]::NewGuid().ToString('N')
)
$InnoTarget = Join-Path $Output 'waptsetup\innosetup'

New-Item -ItemType Directory -Path $InnoTarget -Force | Out-Null

try {
    $innoProcess = Start-Process `
        -FilePath $InnoInstaller `
        -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$InnoTemp" `
        -Wait -PassThru

    if ($innoProcess.ExitCode -ne 0) {
        throw "Inno Setup installation failed with exit code $($innoProcess.ExitCode)"
    }

    foreach ($file in $InnoRootFiles) {
        $src = Join-Path $InnoTemp $file
        Assert-File $src
        Copy-Item -LiteralPath $src -Destination (Join-Path $InnoTarget $file) -Force
    }

    $innoCopied = Get-ChildItem -LiteralPath $InnoTarget -File
    if ($innoCopied.Count -ne 20) {
        throw "Unexpected Inno root file count: expected 20, found $($innoCopied.Count)"
    }

    Write-Host "Controlled Inno root files: 20/20 PASS"

    $InnoLanguagesTarget = Join-Path $InnoTarget 'Languages'
    New-Item -ItemType Directory -Path $InnoLanguagesTarget -Force | Out-Null

    foreach ($file in @(
        'French.isl',
        'German.isl',
        'french.lng'
    )) {
        $src = Join-Path $ProductSource "waptsetup\innosetup\Languages\$file"
        Assert-File $src
        Copy-Item -LiteralPath $src -Destination (Join-Path $InnoLanguagesTarget $file) -Force
    }

    $innoLanguageFiles = Get-ChildItem -LiteralPath $InnoLanguagesTarget -File
    if ($innoLanguageFiles.Count -ne 3) {
        throw "Unexpected Inno language file count: expected 3, found $($innoLanguageFiles.Count)"
    }

    Write-Host "Git-controlled Inno languages: 3/3 PASS"
}
finally {
    if (Test-Path -LiteralPath $InnoTemp) {
        Remove-Item -LiteralPath $InnoTemp -Recurse -Force
    }
}

# ----------------------------------------------------------------------
# Install freshly built Lazarus artifacts
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Installing freshly built Lazarus artifacts..."

foreach ($artifact in $LazarusArtifacts) {
    $src = Join-Path $Worktree $artifact
    Assert-File $src

    $dst = Join-Path $Output $artifact
    $dstDir = Split-Path -Parent $dst

    if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force

    $sourceHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash

    if ($sourceHash -ne $destinationHash) {
        throw "Lazarus artifact hash mismatch after copy: $artifact"
    }
}

Write-Host "[PASS] Fresh Lazarus artifacts installed: 9/9"

# ----------------------------------------------------------------------
# Generate canonical version-full
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Generating canonical version-full..."

$CreateVersionFull = Join-Path $Worktree 'create_version_full.py'
Assert-File $CreateVersionFull

Push-Location $Worktree
try {
    & $WaptPython $CreateVersionFull

    if ($LASTEXITCODE -ne 0) {
        throw "create_version_full.py failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$GeneratedVersionFull = Join-Path $Worktree 'version-full'
Assert-File $GeneratedVersionFull

$VersionFull = (Get-Content -LiteralPath $GeneratedVersionFull -Raw).Trim()

if ($VersionFull -ne $ExpectedFileVersion) {
    throw "version-full mismatch.`nExpected: $ExpectedFileVersion`nActual:   $VersionFull"
}

Copy-Item `
    -LiteralPath $GeneratedVersionFull `
    -Destination (Join-Path $Output 'version-full') `
    -Force

Write-Host "[PASS] version-full generated: $VersionFull"

# ----------------------------------------------------------------------
# Generate canonical revision.txt
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Generating canonical revision.txt..."

$ExpectedRevision = $SourceCommit.Substring(0, 8)
$RevisionTarget = Join-Path $Output 'revision.txt'

[IO.File]::WriteAllText(
    $RevisionTarget,
    $ExpectedRevision,
    [Text.Encoding]::ASCII
)

Assert-File $RevisionTarget

$ActualRevision = (Get-Content -LiteralPath $RevisionTarget -Raw).Trim()

if ($ActualRevision -ne $ExpectedRevision) {
    throw "revision.txt mismatch.`nExpected: $ExpectedRevision`nActual:   $ActualRevision"
}

Write-Host "[PASS] revision.txt generated: $ActualRevision"

# ----------------------------------------------------------------------
# Build unsigned Community setup
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Building unsigned WAPT Community setup..."

$IsccExe = Join-Path $Output 'waptsetup\innosetup\ISCC.exe'
$SetupIss = Join-Path $Output 'waptsetup\waptsetup.iss'
$SetupExe = Join-Path $Output 'waptsetup\waptsetup.exe'

Assert-File $IsccExe
Assert-File $SetupIss

Push-Location $Output
try {
    & $IsccExe '/Dwaptcommunity' '.\waptsetup\waptsetup.iss'

    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Assert-File $SetupExe

Write-Host "[PASS] Unsigned WAPT Community setup built."

# ----------------------------------------------------------------------
# Validate final Community setup
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "Validating final Community setup..."

$SetupItem = Get-Item -LiteralPath $SetupExe
$SetupVersionInfo = $SetupItem.VersionInfo

if ($SetupItem.Length -le 0) {
    throw "Generated setup is empty: $SetupExe"
}

if ($setupVersionInfo.FileVersion.Trim() -ne $ExpectedFileVersion) {
    throw "Setup VersionInfo mismatch.`nExpected: $ExpectedFileVersion`nActual:   $($SetupVersionInfo.FileVersion)"
}
if ($SetupVersionInfo.ProductVersion.Trim() -ne $ExpectedFileVersion) {
    throw "Setup ProductVersion mismatch.`nExpected: $ExpectedFileVersion`nActual:   $($SetupVersionInfo.ProductVersion)"
}

if ($SetupVersionInfo.ProductName.Trim() -ne 'WAPTSetup') {
    throw "Setup ProductName mismatch.`nExpected: WAPTSetup`nActual:   $($SetupVersionInfo.ProductName)"
}

$SetupHash = (Get-FileHash -LiteralPath $SetupExe -Algorithm SHA256).Hash

Write-Host "[PASS] Final Community setup validated."
Write-Host "       FileVersion    : $($SetupVersionInfo.FileVersion)"
Write-Host "       ProductVersion : $($SetupVersionInfo.ProductVersion)"
Write-Host "       ProductName    : $($SetupVersionInfo.ProductName)"
Write-Host "       Size           : $($SetupItem.Length) bytes"
Write-Host "       SHA256         : $SetupHash"

Write-Host ""
Write-Host "[PASS] Base Windows product tree assembled."