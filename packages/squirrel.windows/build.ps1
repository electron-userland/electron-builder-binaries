param (
    # renovate: datasource=github-tags depName=Squirrel/Squirrel.Windows
    [string]$SquirrelVersion = "2.0.1",
    [string]$PatchPath
)

$ErrorActionPreference = "Stop"

# Get-PinnedFile, Get-NuGetCommandLine, Install-BundleLicenses, Install-UpstreamLicenses, Invoke-LicenseGuard
. (Join-Path $PSScriptRoot "build-helpers.ps1")

# Fail now, not after the build, when licenses/UPSTREAM.tsv is malformed or pinned to another Squirrel.Windows version
Read-UpstreamLicenses -Manifest (Join-Path $PSScriptRoot "licenses\UPSTREAM.tsv") -SquirrelVersion $SquirrelVersion | Out-Null

# --- Configuration
$repoRoot      = "C:\s\Squirrel.Windows"
$artifactDir   = Join-Path $PSScriptRoot "out\squirrel.windows"
# Everything in $bundleDir, and nothing else, goes into the zip: electron-winstaller\vendor and LICENSES.
# It is kept apart from build\artifacts, where `nuget pack` writes the Squirrel nupkg that
# electron-builder does not use (earlier releases zipped build\artifacts and shipped that nupkg).
$bundleDir     = Join-Path $repoRoot "build\bundle"
$archivePath   = Join-Path $artifactDir "squirrel.windows-$SquirrelVersion-patched.zip"
if (-not $PatchPath) {
    $PatchPath = Join-Path $PSScriptRoot "patches"
}

# --- Clone source
Write-Host "`n📥 Cloning Squirrel.Windows $SquirrelVersion ..."
if (Test-Path $repoRoot) {
    Remove-Item $repoRoot -Recurse -Force
}
git clone --recursive https://github.com/Squirrel/Squirrel.Windows $repoRoot
Set-Location $repoRoot
git checkout $SquirrelVersion
git submodule update --init --recursive

# --- Optional patches
if ($PatchPath -and (Test-Path $PatchPath) -and (Get-Item $PatchPath).PSIsContainer) {
    foreach ($patch in (Get-ChildItem -Path $PatchPath -Filter *.patch)) {
        Write-Host "`n🔧 Applying patch: $($patch.FullName)"
        git apply $patch.FullName
    }
}

# --- Ensure .NET 4.5 reference assemblies are available
# windows-2022 runners don't ship the .NET 4.5 targeting pack.  The reference-assemblies
# NuGet package provides them but only auto-wires for SDK-style (PackageReference) projects.
# The vendored NuGet source inside Squirrel.Windows uses old-style packages.config, so we
# install the package explicitly and pass FrameworkPathOverride to MSBuild.
Write-Host "`n📦 Installing .NET 4.5 reference assemblies..."
$net45PkgDir = Join-Path $env:TEMP "net45-refassemblies"
# renovate: datasource=nuget depName=Microsoft.NETFramework.ReferenceAssemblies.net45
nuget install Microsoft.NETFramework.ReferenceAssemblies.net45 -Version 1.0.3 `
    -NonInteractive -OutputDirectory $net45PkgDir | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to install .NET 4.5 reference assemblies (exit $LASTEXITCODE)"; exit $LASTEXITCODE }
$net45Path = Join-Path $net45PkgDir "Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.3\build\.NETFramework\v4.5\"
Write-Host "  .NET 4.5 refs: $net45Path"

# --- Run the official build
Write-Host "`n🏗️ Running build steps..."

nuget restore .\Squirrel.sln
if ($LASTEXITCODE -ne 0) { Write-Error "nuget restore failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# PlatformToolset=v143  — retargets C++ projects (Setup, StubExecutable, WriteZipToSetup)
#   from v141 (VS 2017) to v143 (VS 2022). windows-2022 runners ship v143 only.
# FrameworkPathOverride  — points packages.config .NET 4.5 projects at the reference
#   assemblies installed above; without this, MSBuild raises MSB3644 on the vendored
#   nuget source inside Squirrel.Windows.
msbuild -Restore .\Squirrel.sln -p:Configuration=Release -p:PlatformToolset=v143 `
    "-p:FrameworkPathOverride=$net45Path" `
    -v:m -m -nr:false -bl:.\build\logs\build.binlog
if ($LASTEXITCODE -ne 0) { Write-Error "msbuild failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

nuget pack .\src\Squirrel.nuspec -OutputDirectory .\build\artifacts
if ($LASTEXITCODE -ne 0) { Write-Error "nuget pack failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# --- Layout electron-winstaller vendor folder
if (Test-Path $bundleDir) {
    Remove-Item $bundleDir -Recurse -Force
}
$vendorDir = Join-Path $bundleDir "electron-winstaller\vendor"
New-Item -ItemType Directory -Force -Path $vendorDir | Out-Null

# update.com (shipped by earlier releases as Squirrel.com) is not copied: it is a renamed Visual Studio
# devenv.com that neither electron-builder nor Squirrel.exe ever runs.
$copyMap = @{
    ".\build\Release\net45\Update.exe"          = "Squirrel.exe"
    ".\build\Release\net45\Update.pdb"          = "Squirrel.pdb"
    ".\build\Release\Win32\Setup.exe"           = "Setup.exe"
    ".\build\Release\Win32\Setup.pdb"           = "Setup.pdb"
    ".\build\Release\net45\Update-Mono.exe"     = "Squirrel-Mono.exe"
    ".\build\Release\net45\Update-Mono.pdb"     = "Squirrel-Mono.pdb"
    ".\build\Release\Win32\StubExecutable.exe"  = "StubExecutable.exe"
    ".\build\Release\net45\SyncReleases.exe"    = "SyncReleases.exe"
    ".\build\Release\net45\SyncReleases.pdb"    = "SyncReleases.pdb"
    ".\build\Release\Win32\WriteZipToSetup.exe" = "WriteZipToSetup.exe"
    ".\build\Release\Win32\WriteZipToSetup.pdb" = "WriteZipToSetup.pdb"
}

foreach ($src in $copyMap.Keys) {
    Copy-Item $src -Destination (Join-Path $vendorDir $copyMap[$src]) -Force
}
Write-Host "`n✅ Squirrel executables copied."

# Read the COFF Machine field from a PE image (0x8664 = x64, 0xAA64 = arm64, 0x014C = x86).
function Get-PeMachine {
    param ([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $peOffset = [System.BitConverter]::ToInt32($bytes, 0x3C)
    return [System.BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

# --- nuget.exe
# Ship a pinned, checksum-verified standalone nuget.exe. The Chocolatey shim (bin\nuget.exe) resolves
# the real binary relative to its own install path and breaks once relocated to an arbitrary temp dir,
# so the standalone NuGet.CommandLine exe is required. Pinning the download — rather than copying
# whatever version the runner happens to have installed — keeps the bundled binary reproducible and
# in lockstep with the version electron-builder provisions at runtime.
# It is taken from the NuGet.CommandLine package rather than dist.nuget.org's bare nuget.exe (the same
# file) because the package also carries NOTICES.txt for the third-party code built into nuget.exe.
# renovate: datasource=nuget depName=NuGet.CommandLine
$nugetVersion       = "7.9.0"
$nugetPackageSha256 = "FB2074E4427BBF8105F9A5C3DF6DD77105FB82D696C0FC72FC25DA903D1A63B2"
$nugetSha256        = "992D70CAC5B06C38EFEC91806CABA64CDCC07E6D963A0959DBBBAF264D33B800"  # tools\NuGet.exe
Write-Host "`n📦 Downloading pinned NuGet.CommandLine v$nugetVersion..."
$nugetWork = Join-Path $env:TEMP "nuget-commandline-$nugetVersion"
$nuget = Get-NuGetCommandLine -Version $nugetVersion -PackageSha256 $nugetPackageSha256 -ExeSha256 $nugetSha256 `
    -WorkDir $nugetWork
Copy-Item $nuget.Exe (Join-Path $vendorDir "nuget.exe") -Force

# --- 7-Zip binaries
# Squirrel shells out to the full 7-Zip console build (7z.exe + 7z.dll) sitting next to Squirrel.exe
# to pack and unpack nupkgs. Download the official 7-Zip installers at a pinned version and SHA-256
# and extract them, rather than copying whatever 7-Zip the runner happens to have installed.
#
# Ship a pre-selected 7z.exe/dll (x64) plus the arch-specific named copies that select7zipArch in
# electron-builder copies over it to match the build host (os.arch()). Without a matching copy
# (e.g. ia32), the x64 7z.exe is used as-is. arm64 hosts get a native build instead of emulated x64.
# The installers are 7z self-extracting archives; the runner's 7-Zip is only used to unpack them.
# renovate: datasource=github-releases depName=ip7z/7zip
$sevenZipVersion = "26.05"
$sevenZipTag     = $sevenZipVersion -replace '\.', ''
$sevenZipBuilds  = [ordered]@{
    # arch  = installer suffix, SHA-256 of https://github.com/ip7z/7zip/releases/download/<ver>/7z<tag>-<suffix>.exe, PE machine
    "x64"   = @{ Suffix = "x64";   Sha256 = "FD99E86F57D8F429EF5ED045BF98315AF962E2309B0F1BA87A147A44C71647D0"; Machine = 0x8664 }
    "arm64" = @{ Suffix = "arm64"; Sha256 = "86D5790D5DD84CAB4636C3BB7FAB10D3ED7CD3E57E6119401BD2769E28165268"; Machine = 0xAA64 }
}
$extract7z = Join-Path $env:ProgramFiles "7-Zip\7z.exe"
if (-not (Test-Path $extract7z)) {
    Write-Error "7-Zip not found at $extract7z — it is needed to unpack the 7-Zip installers."
    exit 1
}
$sevenZipWork = Join-Path $env:TEMP "7zip-$sevenZipVersion"
if (Test-Path $sevenZipWork) {
    Remove-Item $sevenZipWork -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $sevenZipWork | Out-Null

foreach ($arch in $sevenZipBuilds.Keys) {
    $build = $sevenZipBuilds[$arch]
    Write-Host "`n📦 Downloading pinned 7-Zip $sevenZipVersion ($arch)..."
    $installer = Join-Path $sevenZipWork "7z$sevenZipTag-$($build.Suffix).exe"
    Get-PinnedFile -Url "https://github.com/ip7z/7zip/releases/download/$sevenZipVersion/7z$sevenZipTag-$($build.Suffix).exe" `
        -Sha256 $build.Sha256 -OutFile $installer

    $extractDir = Join-Path $sevenZipWork $arch
    & $extract7z x -y -bd "-o$extractDir" $installer | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to extract $installer (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

    foreach ($f in @("7z.exe", "7z.dll")) {
        $bin = Join-Path $extractDir $f
        if (-not (Test-Path $bin)) { Write-Error "$f not found in $installer"; exit 1 }
        $fileVersion = (Get-Item $bin).VersionInfo.FileVersion
        if (-not $fileVersion -or -not $fileVersion.StartsWith($sevenZipVersion)) {
            Write-Error "$f from $installer has FileVersion '$fileVersion', expected $sevenZipVersion"
            exit 1
        }
        $machine = Get-PeMachine $bin
        if ($machine -ne $build.Machine) {
            Write-Error ("{0} from {1} has PE machine 0x{2:X4}, expected 0x{3:X4}" -f $f, $installer, $machine, $build.Machine)
            exit 1
        }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f)
        $ext  = [System.IO.Path]::GetExtension($f)
        Copy-Item $bin (Join-Path $vendorDir "$base-$arch$ext") -Force
        if ($arch -eq "x64") {
            # Pre-selected default for hosts without a matching arch-specific copy.
            Copy-Item $bin (Join-Path $vendorDir $f) -Force
        }
    }
    Write-Host ("  7z.exe/7z.dll {0} ({1}) bundled." -f $sevenZipVersion, $arch)
}

$7zLicenseSrc = @("License.txt", "license.txt") | ForEach-Object { Join-Path $sevenZipWork "x64\$_" } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $7zLicenseSrc) {
    Write-Error "7-Zip License.txt not found in the x64 installer"
    exit 1
}
Copy-Item $7zLicenseSrc (Join-Path $vendorDir "7z-LICENSE.txt") -Force
Write-Host "  7-Zip license bundled."
Remove-Item $sevenZipWork -Recurse -Force -ErrorAction SilentlyContinue

# --- LICENSE (Squirrel.Windows)
# The Squirrel.Windows repo uses COPYING (not LICENSE) as its license file name.
$licenseSrc = @("COPYING", "LICENSE", "LICENSE.md") | ForEach-Object { Join-Path $repoRoot $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $licenseSrc) {
    Write-Error "LICENSE/COPYING not found in cloned repo at $repoRoot"
    exit 1
}
Copy-Item $licenseSrc (Join-Path $vendorDir "LICENSE") -Force
Write-Host "`n✅ LICENSE copied."

# --- LICENSES (every binary in the bundle; see packages/squirrel.windows/licenses/MANIFEST.tsv)
# The third-party license texts are not in the repo: they are downloaded from the pinned sources in
# licenses/UPSTREAM.tsv, checked against their SHA-256 and written only into the bundle.
Write-Host "`n📜 Laying out LICENSES..."
Install-BundleLicenses -BundleDir $bundleDir `
    -SquirrelVersion $SquirrelVersion `
    -WorkDir (Join-Path $env:TEMP "squirrel-upstream-licenses") `
    -SquirrelLicense $licenseSrc `
    -SemverLicense (Join-Path $repoRoot "src\StubExecutable\LICENSE.md") `
    -SevenZipLicense (Join-Path $vendorDir "7z-LICENSE.txt") `
    -NuGetNotices $nuget.Notices
Remove-Item $nugetWork -Recurse -Force -ErrorAction SilentlyContinue
Invoke-LicenseGuard -BundleDir $bundleDir
Write-Host "✅ Every binary has its license files."

# --- Compress
if (-not (Test-Path $artifactDir)) {
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
}
if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

Set-Location $PSScriptRoot
Write-Host "`n📦 Compressing to: $archivePath"
& 7z a -tzip $archivePath "$bundleDir\*" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compression failed (exit $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host "`n✅ Done!"
Write-Host "🗂️  $archivePath"
Write-Host ("📦 Size: {0:N0} bytes" -f (Get-Item $archivePath).Length)

# --- Clean up
Write-Host "`n🧹 Cleaning up $repoRoot..."
try {
    Remove-Item $repoRoot -Recurse -Force -ErrorAction Stop
    Write-Host "✅ Cleaned up."
} catch {
    Write-Warning "Failed to clean up ${repoRoot}: $_"
}
