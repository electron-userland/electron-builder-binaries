param (
    [string]$SquirrelVersion = "2.0.1",
    [string]$PatchPath
)

$ErrorActionPreference = "Stop"

# --- Configuration
$repoRoot      = "C:\s\Squirrel.Windows"
$artifactDir   = Join-Path $PSScriptRoot "out\squirrel.windows"
$outputDir     = Join-Path $repoRoot "build\artifacts"
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
$vendorDir = Join-Path $outputDir "electron-winstaller\vendor"
New-Item -ItemType Directory -Force -Path $vendorDir | Out-Null

$copyMap = @{
    ".\build\Release\net45\Update.exe"          = "Squirrel.exe"
    ".\build\Release\net45\update.com"          = "Squirrel.com"
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

# --- nuget.exe
# Ship a pinned, checksum-verified standalone nuget.exe. The Chocolatey shim (bin\nuget.exe) resolves
# the real binary relative to its own install path and breaks once relocated to an arbitrary temp dir,
# so the standalone NuGet.CommandLine exe is required. Pinning the download — rather than copying
# whatever version the runner happens to have installed — keeps the bundled binary reproducible and
# in lockstep with the version electron-builder provisions at runtime.
$nugetVersion = "6.14.0"
$nugetSha256  = "92DBED160DDEE0F64B901E907439E021211B428E57C089ECC12FC38DCC4BD9A5"
$nugetUrl     = "https://dist.nuget.org/win-x86-commandline/v$nugetVersion/nuget.exe"
$nugetDest    = Join-Path $vendorDir "nuget.exe"
Write-Host "`n📦 Downloading pinned nuget.exe v$nugetVersion..."
Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetDest -UseBasicParsing
$actualSha = (Get-FileHash -Path $nugetDest -Algorithm SHA256).Hash
if ($actualSha -ne $nugetSha256) {
    Write-Error "nuget.exe checksum mismatch: expected $nugetSha256, got $actualSha"
    exit 1
}
Write-Host "  Source: $nugetUrl (sha256 verified)"

# --- 7-Zip binaries
# Ship both a pre-selected 7z.exe/dll (x64, the host arch on GitHub Actions windows runners)
# and the arch-specific named copies that select7zipArch in electron-builder uses when
# cross-compiling for a different target arch.
Write-Host "`n📦 Bundling 7-Zip binaries..."
$7zDir = "C:\Program Files\7-Zip"
if (-not (Test-Path "$7zDir\7z.exe")) {
    Write-Error "7-Zip not found at $7zDir — ensure 7-Zip is installed on the runner."
    exit 1
}
foreach ($f in @("7z.exe", "7z.dll")) {
    Copy-Item "$7zDir\$f" (Join-Path $vendorDir $f) -Force
}
# x64 arch-specific copies (mirrors what electron-winstaller's npm postinstall script does)
Copy-Item "$7zDir\7z.exe" (Join-Path $vendorDir "7z-x64.exe") -Force
Copy-Item "$7zDir\7z.dll" (Join-Path $vendorDir "7z-x64.dll") -Force
# Bundle 7-Zip license files alongside the binaries
$7zLicenseSrc = @("License.txt", "license.txt") | ForEach-Object { Join-Path $7zDir $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($7zLicenseSrc) {
    Copy-Item $7zLicenseSrc (Join-Path $vendorDir "7z-LICENSE.txt") -Force
    Write-Host "  7z x64 binaries and license bundled."
} else {
    Write-Warning "7-Zip License.txt not found at $7zDir — skipping."
    Write-Host "  7z x64 binaries bundled (no license file found)."
}

# --- LICENSE (Squirrel.Windows)
# The Squirrel.Windows repo uses COPYING (not LICENSE) as its license file name.
$licenseSrc = @("COPYING", "LICENSE", "LICENSE.md") | ForEach-Object { Join-Path $repoRoot $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $licenseSrc) {
    Write-Error "LICENSE/COPYING not found in cloned repo at $repoRoot"
    exit 1
}
Copy-Item $licenseSrc (Join-Path $vendorDir "LICENSE") -Force
Write-Host "`n✅ LICENSE copied."

# --- Compress
if (-not (Test-Path $artifactDir)) {
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
}
if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

Set-Location $PSScriptRoot
Write-Host "`n📦 Compressing to: $archivePath"
& 7z a -tzip $archivePath "$outputDir\*" | Out-Null
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
