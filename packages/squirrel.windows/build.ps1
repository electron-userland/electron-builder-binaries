param (
    [string]$SquirrelVersion = "2.0.1",
    [string]$PatchPath
)

$ErrorActionPreference = "Stop"

# --- Configuration
$repoRoot = "C:\s\Squirrel.Windows"
$artifactDir = Join-Path $PSScriptRoot "out\squirrel.windows"
$outputDir = Join-Path $repoRoot "build\artifacts"
$archivePath = Join-Path $artifactDir "squirrel.windows-$SquirrelVersion-patched.7z"
if (-not $PatchPath) {
    $PatchPath = Join-Path $PSScriptRoot "patches"
}

# --- Clone source
Write-Host "`n📥 Cloning Squirrel.Windows..."
if (Test-Path $repoRoot) {
    Remove-Item $repoRoot -Recurse -Force
}
git clone --recursive https://github.com/Squirrel/Squirrel.Windows $repoRoot
Set-Location $repoRoot
git checkout $SquirrelVersion
git submodule update --init --recursive

# --- Optional patches
if ($PatchPath -and (Test-Path $PatchPath) -and (Get-Item $PatchPath).PSIsContainer) {
    $patchFiles = Get-ChildItem -Path $PatchPath -Filter *.patch

    foreach ($patch in $patchFiles) {
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
    ".\build\Release\net45\Update.exe"              = "Squirrel.exe"
    ".\build\Release\net45\update.com"              = "Squirrel.com"
    ".\build\Release\net45\Update.pdb"              = "Squirrel.pdb"
    ".\build\Release\Win32\Setup.exe"               = "Setup.exe"
    ".\build\Release\Win32\Setup.pdb"               = "Setup.pdb"
    ".\build\Release\net45\Update-Mono.exe"         = "Squirrel-Mono.exe"
    ".\build\Release\net45\Update-Mono.pdb"         = "Squirrel-Mono.pdb"
    ".\build\Release\Win32\StubExecutable.exe"      = "StubExecutable.exe"
    ".\build\Release\net45\SyncReleases.exe"        = "SyncReleases.exe"
    ".\build\Release\net45\SyncReleases.pdb"        = "SyncReleases.pdb"
    ".\build\Release\Win32\WriteZipToSetup.exe"     = "WriteZipToSetup.exe"
    ".\build\Release\Win32\WriteZipToSetup.pdb"     = "WriteZipToSetup.pdb"
}

foreach ($src in $copyMap.Keys) {
    $dest = Join-Path $vendorDir $copyMap[$src]
    Copy-Item $src -Destination $dest -Force
}

Write-Host "`n✅ Build completed successfully!"

# --- Copy LICENSE from cloned repo before cleanup
$licenseSrc = Join-Path $repoRoot "LICENSE"
$licenseDest = Join-Path $vendorDir "LICENSE"
if (Test-Path $licenseSrc) {
    Copy-Item $licenseSrc -Destination $licenseDest -Force
    Write-Host "`n✅ LICENSE copied to vendor directory"
} else {
    Write-Error "`n⚠️ LICENSE not found in cloned repo at $licenseSrc"
    exit 1
}

# --- Ensure output directory exists
if (-not (Test-Path $artifactDir)) {
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
}

# --- Compress the output
if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

Write-Host "`n📦 Compressing to: $archivePath"
& 7z a -t7z -mx=9 $archivePath "$outputDir\*" | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Compression failed"
    exit $LASTEXITCODE
}

Write-Host "`n✅ Done!"
Write-Host "🗂️ Archive located at: $archivePath"
Write-Host ("📦 Archive size: {0:N0} bytes" -f (Get-Item $archivePath).Length)

# --- Clean up repo root
Write-Host "`n🧹 Cleaning up $repoRoot..."
try {
    Set-Location $PSScriptRoot  # Ensure we’re not inside $repoRoot
    Remove-Item $repoRoot -Recurse -Force -ErrorAction Stop
    Write-Host "✅ Repo root cleaned up successfully."
}
catch {
    Write-Warning "⚠️ Failed to clean up ${repoRoot}: $_"
}