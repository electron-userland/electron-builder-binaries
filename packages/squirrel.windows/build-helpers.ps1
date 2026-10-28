# Helpers for build.ps1 (dot-sourced). Kept free of Windows-only paths so the download, license and
# guard steps can also be run on their own, e.g. with PowerShell on Linux or macOS.

# --- Pinned downloads
# Download a file and fail unless its SHA-256 matches the pinned value. Retries transient network
# failures (connection resets, timeouts) — these throw rather than returning an HTTP status, so
# Invoke-WebRequest's own -MaximumRetryCount would not cover them.
# -UserAgent replaces PowerShell's browser-like default ("Mozilla/5.0 ... PowerShell/7.x"), for which
# SourceForge answers with an HTML download page instead of the file.
function Get-PinnedFile {
    param (
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$OutFile,
        [string]$UserAgent
    )
    $request = @{ Uri = $Url; OutFile = $OutFile; UseBasicParsing = $true }
    if ($UserAgent) { $request.UserAgent = $UserAgent }
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Invoke-WebRequest @request
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
# Lay out <bundle>/LICENSES per scripts/verify-licenses.sh: the committed licenses/ directory (MANIFEST.tsv,
# UPSTREAM.tsv and SOURCES.md, no license texts), the third-party license texts UPSTREAM.tsv lists, downloaded
# and checked now, and the license files taken from the build inputs themselves.
function Install-BundleLicenses {
    param (
        [Parameter(Mandatory)][string]$BundleDir,
        [Parameter(Mandatory)][string]$SquirrelVersion,  # the Squirrel.Windows tag UPSTREAM.tsv must be pinned to
        [Parameter(Mandatory)][string]$WorkDir,          # scratch directory for the downloads (deleted afterwards)
        [Parameter(Mandatory)][string]$SquirrelLicense,  # COPYING of the Squirrel.Windows checkout
        [Parameter(Mandatory)][string]$SemverLicense,    # src/StubExecutable/LICENSE.md of the checkout
        [Parameter(Mandatory)][string]$SevenZipLicense,  # License.txt of the 7-Zip installer
        [Parameter(Mandatory)][string]$NuGetNotices      # NOTICES.txt of NuGet.CommandLine
    )
    $licensesDir = Join-Path $BundleDir "LICENSES"
    if (Test-Path $licensesDir) {
        Remove-Item $licensesDir -Recurse -Force
    }
    $committed = Join-Path $PSScriptRoot "licenses"
    New-Item -ItemType Directory -Force -Path $licensesDir | Out-Null
    foreach ($name in @("MANIFEST.tsv", "UPSTREAM.tsv", "SOURCES.md")) {
        Copy-Item (Join-Path $committed $name) -Destination (Join-Path $licensesDir $name)
    }

    Install-UpstreamLicenses -Manifest (Join-Path $committed "UPSTREAM.tsv") -LicensesDir $licensesDir `
        -WorkDir $WorkDir -SquirrelVersion $SquirrelVersion

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

# Parse UPSTREAM.tsv (see its header) into one object per license file. Throws on a malformed line and when its
# "# squirrel-version:" line is not $SquirrelVersion.
function Read-UpstreamLicenses {
    param (
        [Parameter(Mandatory)][string]$Manifest,
        [Parameter(Mandatory)][string]$SquirrelVersion
    )
    if (-not (Test-Path $Manifest -PathType Leaf)) { throw "$Manifest not found" }
    $sha = '^[0-9a-fA-F]{64}$'
    $name = '^[A-Za-z0-9][A-Za-z0-9._-]*$'  # one path segment: no / \ or ..
    $pinned = $null
    $entries = @()
    $seen = @{}
    $n = 0
    foreach ($raw in [System.IO.File]::ReadAllLines($Manifest)) {
        $n++
        $line = $raw.TrimEnd("`r")
        if ($line -match '^#\s*squirrel-version:\s*(\S+)\s*$') { $pinned = $Matches[1]; continue }
        if ($line -match '^\s*(#|$)') { continue }
        $where = "${Manifest}:$n"
        $f = $line -split "`t"
        if ($f.Count -ne 5 -and $f.Count -ne 7) {
            throw "${where}: expected 5 or 7 tab-separated columns, got $($f.Count)"
        }
        $e = [pscustomobject]@{
            Component = $f[0]; Version = $f[1]; File = $f[2]; Sha256 = $f[3].ToUpperInvariant(); Url = $f[4]
            SourceSha256 = $null; Extract = $null; Line = $where
        }
        if ($e.Component -notmatch $name -or $e.File -notmatch $name -or $e.Component -match '\.\.' -or $e.File -match '\.\.') {
            throw "${where}: component and file must be plain names (got '$($e.Component)' / '$($e.File)')"
        }
        if ($e.Sha256 -notmatch $sha) { throw "${where}: sha256 '$($f[3])' is not 64 hex digits" }
        if ($e.Url -notmatch '^https://') { throw "${where}: url must be https:// (got '$($e.Url)')" }
        if ($f.Count -eq 7) {
            $e.SourceSha256 = $f[5].ToUpperInvariant()
            $e.Extract = $f[6]
            if ($e.SourceSha256 -notmatch $sha) { throw "${where}: source-sha256 '$($f[5])' is not 64 hex digits" }
            if ($e.Extract -notmatch '^(zip:.+|lines:[1-9][0-9]*-[1-9][0-9]*)$') {
                throw "${where}: extract must be zip:<entry> or lines:<first>-<last> (got '$($e.Extract)')"
            }
        }
        $key = "$($e.Component)/$($e.File)".ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "${where}: $($e.Component)/$($e.File) is listed twice" }
        $seen[$key] = $true
        $entries += $e
    }
    if (-not $pinned) { throw "${Manifest}: no '# squirrel-version: <tag>' line" }
    if ($pinned -ne $SquirrelVersion) {
        throw "${Manifest} is pinned to Squirrel.Windows $pinned but the build is for ${SquirrelVersion}: re-check every version and SHA-256 in it"
    }
    if ($entries.Count -eq 0) { throw "${Manifest}: lists no license files" }
    return $entries
}

# Lines <First>..<Last> of a text file, byte for byte (line endings and any BOM kept), like sed -n 'First,Lastp'.
function Get-LineRangeBytes {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$First,
        [Parameter(Mandatory)][int]$Last
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $starts = [System.Collections.Generic.List[int]]::new()
    $starts.Add(0)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10 -and $i + 1 -lt $bytes.Length) { $starts.Add($i + 1) }
    }
    if ($bytes.Length -eq 0 -or $First -gt $Last -or $Last -gt $starts.Count) {
        throw "${Path}: lines $First-$Last are out of range (it has $($starts.Count) lines)"
    }
    $from = $starts[$First - 1]
    $to = if ($Last -lt $starts.Count) { $starts[$Last] } else { $bytes.Length }
    # The comma keeps the array whole instead of sending it down the pipeline byte by byte
    return ,([byte[]]$bytes[$from..($to - 1)])
}

# Download every license file UPSTREAM.tsv lists into <LicensesDir>/<component>/<file>. Each download is checked
# against its pinned SHA-256 (Get-PinnedFile), and so is each file extracted from one; any mismatch, failed
# download, missing zip entry or line range ends the build.
function Install-UpstreamLicenses {
    param (
        [Parameter(Mandatory)][string]$Manifest,
        [Parameter(Mandatory)][string]$LicensesDir,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$SquirrelVersion
    )
    $entries = Read-UpstreamLicenses -Manifest $Manifest -SquirrelVersion $SquirrelVersion
    if (Test-Path $WorkDir) {
        Remove-Item $WorkDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $i = 0
    foreach ($e in $entries) {
        $i++
        $label = "LICENSES/$($e.Component)/$($e.File)"
        $download = Join-Path $WorkDir ("{0:D2}-{1}" -f $i, [System.IO.Path]::GetFileName(([uri]$e.Url).AbsolutePath))
        $downloadSha = if ($e.Extract) { $e.SourceSha256 } else { $e.Sha256 }
        Write-Host "  $label ($($e.Component) $($e.Version))"
        Get-PinnedFile -Url $e.Url -Sha256 $downloadSha -OutFile $download -UserAgent "electron-builder-binaries"

        $componentDir = Join-Path $LicensesDir $e.Component
        New-Item -ItemType Directory -Force -Path $componentDir | Out-Null
        $dest = Join-Path $componentDir $e.File
        if (-not $e.Extract) {
            Copy-Item $download -Destination $dest -Force
        } elseif ($e.Extract -like "zip:*") {
            $entryName = $e.Extract.Substring(4)
            $zip = [System.IO.Compression.ZipFile]::OpenRead($download)
            try {
                $entry = $zip.GetEntry($entryName)
                if (-not $entry) { throw "$($e.Line): $entryName not found in $($e.Url)" }
                $in = $entry.Open()
                $out = [System.IO.File]::Create($dest)
                try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
            } finally {
                $zip.Dispose()
            }
        } else {
            $first, $last = $e.Extract.Substring(6) -split "-" | ForEach-Object { [int]$_ }
            [System.IO.File]::WriteAllBytes($dest, (Get-LineRangeBytes -Path $download -First $first -Last $last))
        }

        $actual = (Get-FileHash -Path $dest -Algorithm SHA256).Hash
        if ($actual -ne $e.Sha256) {
            throw "Checksum mismatch for $label ($($e.Extract) of $($e.Url)): expected $($e.Sha256), got $actual"
        }
        if ((Get-Item $dest).Length -eq 0) { throw "$label is empty" }
    }
    Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  $($entries.Count) upstream license files downloaded and verified"
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
