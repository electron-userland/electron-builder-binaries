param (
    [string]$SquirrelVersion = "2.0.1",
    [string]$PatchPath
)

$ErrorActionPreference = "Stop"

# --- Configuration
$repoRoot      = "C:\s\Squirrel.Windows"
$artifactDir   = Join-Path $PSScriptRoot "out\squirrel.windows"
$outputDir     = Join-Path $repoRoot "build\artifacts"
$archivePath   = Join-Path $artifactDir "squirrel.windows-$SquirrelVersion-patched.7z"
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

# --- Run the official build
Write-Host "`n🏗️ Running build steps..."
nuget restore .\Squirrel.sln
msbuild -Restore .\Squirrel.sln -p:Configuration=Release -v:m -m -nr:false -bl:.\build\logs\build.binlog
nuget pack .\src\Squirrel.nuspec -OutputDirectory .\build\artifacts

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
# The build already ran `nuget restore` and `nuget pack`, so nuget.exe is guaranteed
# to be in PATH. Capture it here so it ships inside the vendor bundle and does not
# need to be downloaded at runtime on end-user machines.
Write-Host "`n📦 Bundling nuget.exe..."
$nugetSrc = (Get-Command nuget.exe -ErrorAction Stop).Source
Copy-Item $nugetSrc (Join-Path $vendorDir "nuget.exe") -Force
Write-Host "  Source: $nugetSrc"

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
Write-Host "  7z x64 binaries bundled."

# --- LICENSE
$licenseSrc = Join-Path $repoRoot "LICENSE"
if (-not (Test-Path $licenseSrc)) {
    Write-Error "LICENSE not found in cloned repo at $licenseSrc"
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
& 7z a -t7z -mx=9 $archivePath "$outputDir\*" | Out-Null
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
