# Helpers for build.ps1 (dot-sourced). Kept free of Windows-only paths so the download, license and
# guard steps can also be run on their own, e.g. with PowerShell on Linux or macOS.

# --- Pinned downloads
# Download a file and fail unless its SHA-256 matches the pinned value. Retries transient network
# failures (connection resets, timeouts) — these throw rather than returning an HTTP status, so
# Invoke-WebRequest's own -MaximumRetryCount would not cover them.
function Get-PinnedFile {
    param (
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$OutFile
    )
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
            break
        } catch {
            if ($attempt -eq $maxAttempts) {
                Write-Error "Failed to download $Url after $maxAttempts attempts: $_"
                exit 1
            }
            Write-Warning "Download attempt $attempt/$maxAttempts for $Url failed: $_. Retrying in 5s..."
            Start-Sleep -Seconds 5
        }
    }
    $actualSha = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash
    if ($actualSha -ne $Sha256) {
        Write-Error "Checksum mismatch for ${Url}: expected $Sha256, got $actualSha"
        exit 1
    }
    Write-Host "  Source: $Url (sha256 verified)"
}

# --- NuGet.CommandLine
# Download the pinned NuGet.CommandLine package and unpack it into $WorkDir. Returns the paths of
# tools/NuGet.exe (checked against $ExeSha256) and of the package's NOTICES.txt, which lists the
# third-party code built into NuGet.exe and has to ship next to it.
function Get-NuGetCommandLine {
    param (
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$PackageSha256,
        [Parameter(Mandatory)][string]$ExeSha256,
        [Parameter(Mandatory)][string]$WorkDir
    )
    if (Test-Path $WorkDir) {
        Remove-Item $WorkDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $id = "nuget.commandline"
    $package = Join-Path $WorkDir "$id.$Version.nupkg"
    Get-PinnedFile -Url "https://api.nuget.org/v3-flatcontainer/$id/$Version/$id.$Version.nupkg" `
        -Sha256 $PackageSha256 -OutFile $package

    # A .nupkg is a zip archive. ZipFile (unlike Expand-Archive) does not insist on a .zip extension.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $extractDir = Join-Path $WorkDir "package"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($package, $extractDir)

    $exe = Join-Path (Join-Path $extractDir "tools") "NuGet.exe"
    $notices = Join-Path $extractDir "NOTICES.txt"
    foreach ($f in @($exe, $notices)) {
        if (-not (Test-Path $f -PathType Leaf)) { throw "$f not found in NuGet.CommandLine $Version" }
    }
    $actualSha = (Get-FileHash -Path $exe -Algorithm SHA256).Hash
    if ($actualSha -ne $ExeSha256) {
        throw "Checksum mismatch for NuGet.exe in NuGet.CommandLine ${Version}: expected $ExeSha256, got $actualSha"
    }
    return [pscustomobject]@{ Exe = $exe; Notices = $notices }
}

# --- Licenses
# Lay out <bundle>/LICENSES per scripts/verify-licenses.sh: the committed licenses/ directory
# (MANIFEST.tsv, SOURCES.md and the third-party license texts) plus the license files taken from
# the build inputs themselves.
function Install-BundleLicenses {
    param (
        [Parameter(Mandatory)][string]$BundleDir,
        [Parameter(Mandatory)][string]$SquirrelLicense,  # COPYING of the Squirrel.Windows checkout
        [Parameter(Mandatory)][string]$SemverLicense,    # src/StubExecutable/LICENSE.md of the checkout
        [Parameter(Mandatory)][string]$SevenZipLicense,  # License.txt of the 7-Zip installer
        [Parameter(Mandatory)][string]$NuGetNotices      # NOTICES.txt of NuGet.CommandLine
    )
    $licensesDir = Join-Path $BundleDir "LICENSES"
    if (Test-Path $licensesDir) {
        Remove-Item $licensesDir -Recurse -Force
    }
    Copy-Item (Join-Path $PSScriptRoot "licenses") -Destination $licensesDir -Recurse

    $fromBuild = [ordered]@{
        "squirrel-windows/COPYING"      = $SquirrelLicense
        "semver/LICENSE.md"             = $SemverLicense
        "7-zip/License.txt"             = $SevenZipLicense
        "nuget-commandline/NOTICES.txt" = $NuGetNotices
    }
    foreach ($dest in $fromBuild.Keys) {
        $src = $fromBuild[$dest]
        if (-not (Test-Path $src -PathType Leaf) -or (Get-Item $src).Length -eq 0) {
            throw "License file $src (for LICENSES/$dest) is missing or empty"
        }
        $component, $name = $dest -split "/"
        $componentDir = Join-Path $licensesDir $component
        New-Item -ItemType Directory -Force -Path $componentDir | Out-Null
        Copy-Item $src -Destination (Join-Path $componentDir $name) -Force
    }
    Write-Host "  Licenses laid out in $licensesDir"
}

# Run scripts/verify-licenses.sh on the bundle with bash (Git Bash on Windows) and fail the build
# when a binary has no license files.
function Invoke-LicenseGuard {
    param ([Parameter(Mandatory)][string]$BundleDir)

    $bash = $null
    if ($env:ProgramFiles) {
        # Prefer Git Bash: a bare "bash" on Windows can resolve to the WSL launcher in System32.
        $gitBash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        if (Test-Path $gitBash) { $bash = $gitBash }
    }
    if (-not $bash) {
        $bash = (Get-Command bash -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    }
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $guard = Join-Path (Join-Path $repoRoot "scripts") "verify-licenses.sh"
    # Git Bash takes C:/x/y; forward slashes are also what bash expects elsewhere.
    $guardArg = ([System.IO.Path]::GetFullPath($guard)) -replace '\\', '/'
    $bundleArg = ([System.IO.Path]::GetFullPath($BundleDir)) -replace '\\', '/'
    & $bash $guardArg $bundleArg
    if ($LASTEXITCODE -ne 0) {
        throw "License check failed for $BundleDir (exit $LASTEXITCODE): every binary needs an entry in packages/squirrel.windows/licenses/MANIFEST.tsv"
    }
}
