# Self-test for the build-time license download (Install-UpstreamLicenses in build-helpers.ps1) and for
# licenses/UPSTREAM.tsv. Every download is stubbed: a stand-in Invoke-WebRequest serves local fixture files, so the
# test needs no network. Each case runs build-helpers.ps1 in its own pwsh process, as build.ps1 does, because a
# failed download or checksum ends that process.
#
# Run: pwsh -NoProfile -File packages/squirrel.windows/test/upstream-licenses-test.ps1 [-Live]
#   -Live  also downloads every file the real UPSTREAM.tsv lists and checks its SHA-256 (needs network)
param ([switch]$Live)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3

$pkgDir    = Split-Path $PSScriptRoot -Parent
$helpers   = Join-Path $pkgDir "build-helpers.ps1"
$upstream  = Join-Path (Join-Path $pkgDir "licenses") "UPSTREAM.tsv"
$manifest  = Join-Path (Join-Path $pkgDir "licenses") "MANIFEST.tsv"
$pwsh      = (Get-Process -Id $PID).Path
$work      = Join-Path ([System.IO.Path]::GetTempPath()) ("upstream-licenses-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

$script:failures = 0
function Pass([string]$desc) { Write-Host "✓ $desc" }
function Fail([string]$desc, [string]$detail) {
    Write-Host "❌ $desc"
    if ($detail) { $detail -split "`n" | ForEach-Object { Write-Host "     $_" } }
    $script:failures++
}
function Sha([byte[]]$bytes) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($h.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Bytes([string]$text) { return [System.Text.Encoding]::UTF8.GetBytes($text) }

# --- Fixtures: what the stub "downloads". The stub serves https://fixtures.invalid/<name> from $fixtures/<name>.
$fixtures = Join-Path $work "fixtures"
New-Item -ItemType Directory -Path $fixtures | Out-Null

$licenseBytes = Bytes "MIT License`n`nCopyright (c) stand-in`n"
[System.IO.File]::WriteAllBytes((Join-Path $fixtures "LICENSE.txt"), $licenseBytes)

# A source file with a BOM and CRLF line endings: lines 2-4 are its license header
$bom = [byte[]](0xEF, 0xBB, 0xBF)
$headerFile = $bom + (Bytes "// file.cs`r`n// Copyright (c) stand-in`r`n// Permission is hereby granted`r`n// THE SOFTWARE IS PROVIDED AS IS`r`nnamespace X {}`r`n")
[System.IO.File]::WriteAllBytes((Join-Path $fixtures "file.cs"), $headerFile)
$headerBytes = Bytes "// Copyright (c) stand-in`r`n// Permission is hereby granted`r`n// THE SOFTWARE IS PROVIDED AS IS`r`n"
# The first line keeps the BOM, as sed -n '1,1p' would
$firstLineBytes = $bom + (Bytes "// file.cs`r`n")
# A last line without a newline
$noEolBytes = Bytes "line 1`nline 2"
[System.IO.File]::WriteAllBytes((Join-Path $fixtures "noeol.txt"), $noEolBytes)

# A nupkg (zip) with the license file in it
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$nuspecBytes = Bytes "<?xml version=`"1.0`"?>`r`n<package><metadata><copyright>stand-in</copyright></metadata></package>"
$zipPath = Join-Path $fixtures "pkg.1.0.0.nupkg"
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($e in @(@{ Name = "Pkg.nuspec"; Bytes = $nuspecBytes }, @{ Name = "lib/net45/Pkg.dll"; Bytes = (Bytes "MZ stand-in") })) {
        $s = $zip.CreateEntry($e.Name).Open()
        try { $s.Write($e.Bytes, 0, $e.Bytes.Length) } finally { $s.Dispose() }
    }
} finally { $zip.Dispose() }
$zipSha = Sha ([System.IO.File]::ReadAllBytes($zipPath))

$shaLicense = Sha $licenseBytes
$shaHeaderFile = Sha $headerFile
$shaHeader = Sha $headerBytes
$shaNuspec = Sha $nuspecBytes
$wrongSha = "0" * 64
$base = "https://fixtures.invalid"

# --- The runner: stubs the network, dot-sources build-helpers.ps1 and runs Install-UpstreamLicenses
$runner = Join-Path $work "run.ps1"
Set-Content -Path $runner -Encoding utf8 -Value @'
param ([string]$Helpers, [string]$Manifest, [string]$LicensesDir, [string]$WorkDir, [string]$Fixtures, [string]$Version)
$ErrorActionPreference = "Stop"
# Functions take precedence over cmdlets, so Get-PinnedFile calls these instead of the real ones
function Invoke-WebRequest {
    param ([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, [string]$UserAgent)
    $src = Join-Path $Fixtures ([uri]$Uri).Segments[-1]
    if (-not (Test-Path $src -PathType Leaf)) { throw "Response status code does not indicate success: 404 (Not Found)." }
    Copy-Item $src $OutFile
}
function Start-Sleep { }
. $Helpers
Install-UpstreamLicenses -Manifest $Manifest -LicensesDir $LicensesDir -WorkDir $WorkDir -SquirrelVersion $Version
'@

$caseNo = 0
# Run-Case <description> <pass|fail> <manifest lines> [-Version v] [-Expect regex...] [-Files @{ "component/file" = bytes }]
function Run-Case {
    param (
        [string]$Desc, [string]$Want, [string[]]$Lines, [string]$Version = "9.9.9",
        [string[]]$Expect = @(), [hashtable]$Files = @{}, [string]$Header = "# squirrel-version: 9.9.9"
    )
    $script:caseNo++
    $dir = Join-Path $work ("case{0:D2}" -f $script:caseNo)
    New-Item -ItemType Directory -Path $dir | Out-Null
    $m = Join-Path $dir "UPSTREAM.tsv"
    # CRLF, as a Windows checkout with core.autocrlf has it
    [System.IO.File]::WriteAllText($m, ((@("# test manifest", $Header) + $Lines) -join "`r`n") + "`r`n")
    $licenses = Join-Path $dir "LICENSES"
    $downloads = Join-Path $dir "downloads"
    $out = & $pwsh -NoProfile -NonInteractive -File $runner -Helpers $helpers -Manifest $m -LicensesDir $licenses `
        -WorkDir $downloads -Fixtures $fixtures -Version $Version 2>&1 | Out-String
    $rc = $LASTEXITCODE
    $got = if ($rc -eq 0) { "pass" } else { "fail" }
    if ($got -ne $Want) { Fail "${Desc}: expected $Want, got $got (exit $rc)" $out; return }
    foreach ($pattern in $Expect) {
        if ($out -notmatch $pattern) { Fail "${Desc}: output does not match /$pattern/" $out; return }
    }
    foreach ($rel in $Files.Keys) {
        $path = Join-Path $licenses $rel
        if (-not (Test-Path $path -PathType Leaf)) { Fail "${Desc}: LICENSES/$rel was not written" $out; return }
        $actual = [System.IO.File]::ReadAllBytes($path)
        if ((Sha $actual) -ne (Sha $Files[$rel])) { Fail "${Desc}: LICENSES/$rel does not have the expected bytes" $out; return }
    }
    if ($Want -eq "pass" -and (Test-Path $downloads)) { Fail "${Desc}: the download directory was left behind" $out; return }
    Pass $Desc
}

function Row([string[]]$cols) { return ($cols -join "`t") }

try {
    # --- Happy path: a plain download, a file taken out of a nupkg and a license header taken out of a source file
    Run-Case "plain, zip and line-range files are downloaded, verified and written" pass @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense, "$base/LICENSE.txt"),
        (Row "pkg", "1.0.0", "Pkg.nuspec", $shaNuspec, "$base/pkg.1.0.0.nupkg", $zipSha, "zip:Pkg.nuspec"),
        (Row "header", "9.9.9", "NOTICE.txt", $shaHeader, "$base/file.cs", $shaHeaderFile, "lines:2-4"),
        (Row "first", "9.9.9", "NOTICE.txt", (Sha $firstLineBytes), "$base/file.cs", $shaHeaderFile, "lines:1-1"),
        (Row "noeol", "1.0", "LAST.txt", (Sha (Bytes "line 2")), "$base/noeol.txt", (Sha $noEolBytes), "lines:2-2")
    ) -Expect @("5 upstream license files downloaded and verified") -Files @{
        "plain/LICENSE.txt" = $licenseBytes; "pkg/Pkg.nuspec" = $nuspecBytes; "header/NOTICE.txt" = $headerBytes
        "first/NOTICE.txt" = $firstLineBytes; "noeol/LAST.txt" = (Bytes "line 2")
    }
    Run-Case "upper-case SHA-256s are accepted" pass @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense.ToUpperInvariant(), "$base/LICENSE.txt")
    ) -Files @{ "plain/LICENSE.txt" = $licenseBytes }

    # --- Checksum mismatches
    Run-Case "a download whose SHA-256 differs fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", $wrongSha, "$base/LICENSE.txt")
    ) -Expect @("Checksum mismatch for https://fixtures.invalid/LICENSE.txt")
    Run-Case "a nupkg whose SHA-256 differs fails" fail @(
        (Row "pkg", "1.0.0", "Pkg.nuspec", $shaNuspec, "$base/pkg.1.0.0.nupkg", $wrongSha, "zip:Pkg.nuspec")
    ) -Expect @("Checksum mismatch for https://fixtures.invalid/pkg.1.0.0.nupkg")
    Run-Case "a file extracted from a nupkg whose SHA-256 differs fails" fail @(
        (Row "pkg", "1.0.0", "Pkg.nuspec", $wrongSha, "$base/pkg.1.0.0.nupkg", $zipSha, "zip:Pkg.nuspec")
    ) -Expect @("Checksum mismatch for LICENSES/pkg/Pkg.nuspec")
    Run-Case "a line range whose SHA-256 differs fails" fail @(
        (Row "header", "9.9.9", "NOTICE.txt", $shaHeader, "$base/file.cs", $shaHeaderFile, "lines:2-5")
    ) -Expect @("Checksum mismatch for LICENSES/header/NOTICE.txt")
    Run-Case "a mismatch after good files still fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense, "$base/LICENSE.txt"),
        (Row "other", "1.0", "LICENSE.txt", $wrongSha, "$base/LICENSE.txt")
    ) -Expect @("Checksum mismatch")

    # --- Missing files
    Run-Case "a download that is not found fails" fail @(
        (Row "gone", "1.0", "LICENSE.txt", $shaLicense, "$base/missing.txt")
    ) -Expect @("Failed to download https://fixtures.invalid/missing.txt after 3 attempts")
    Run-Case "a zip entry that is not in the nupkg fails" fail @(
        (Row "pkg", "1.0.0", "LICENSE.txt", $shaNuspec, "$base/pkg.1.0.0.nupkg", $zipSha, "zip:LICENSE.txt")
    ) -Expect @("LICENSE.txt not found in https://fixtures.invalid/pkg.1.0.0.nupkg")
    Run-Case "a line range past the end of the file fails" fail @(
        (Row "header", "9.9.9", "NOTICE.txt", $shaHeader, "$base/file.cs", $shaHeaderFile, "lines:4-9")
    ) -Expect @("lines 4-9 are out of range \(it has 5 lines\)")

    # --- Manifest errors
    Run-Case "a manifest pinned to another Squirrel.Windows version fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense, "$base/LICENSE.txt")
    ) -Version "2.0.2" -Expect @("pinned to Squirrel.Windows 9.9.9 but the build is for 2.0.2")
    Run-Case "a manifest without a squirrel-version line fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense, "$base/LICENSE.txt")
    ) -Header "#" -Expect @("no '# squirrel-version: <tag>' line")
    Run-Case "a line with a missing column fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense)
    ) -Expect @("expected 5 or 7 tab-separated columns, got 4")
    Run-Case "a path outside LICENSES/<component>/ fails" fail @(
        (Row "..", "1.0", "LICENSE.txt", $shaLicense, "$base/LICENSE.txt")
    ) -Expect @("component and file must be plain names")
    Run-Case "a file name with a directory fails" fail @(
        (Row "plain", "1.0", "sub/LICENSE.txt", $shaLicense, "$base/LICENSE.txt")
    ) -Expect @("component and file must be plain names")
    Run-Case "a short SHA-256 fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", "abc123", "$base/LICENSE.txt")
    ) -Expect @("sha256 'abc123' is not 64 hex digits")
    Run-Case "a plain http:// URL fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense, "http://fixtures.invalid/LICENSE.txt")
    ) -Expect @("url must be https://")
    Run-Case "an unknown extract kind fails" fail @(
        (Row "pkg", "1.0.0", "Pkg.nuspec", $shaNuspec, "$base/pkg.1.0.0.nupkg", $zipSha, "tar:Pkg.nuspec")
    ) -Expect @("extract must be zip:<entry> or lines:<first>-<last>")
    Run-Case "a file listed twice fails" fail @(
        (Row "plain", "1.0", "LICENSE.txt", $shaLicense, "$base/LICENSE.txt"),
        (Row "plain", "1.0", "license.txt", $shaLicense, "$base/LICENSE.txt")
    ) -Expect @("is listed twice")
    Run-Case "an empty manifest fails" fail @() -Expect @("lists no license files")

    # --- The real UPSTREAM.tsv
    . $helpers
    $buildPs1 = Get-Content (Join-Path $pkgDir "build.ps1") -Raw
    if ($buildPs1 -notmatch '\[string\]\$SquirrelVersion\s*=\s*"([^"]+)"') { throw "No default `$SquirrelVersion in build.ps1" }
    $squirrelVersion = $Matches[1]
    $entries = $null
    try {
        $entries = Read-UpstreamLicenses -Manifest $upstream -SquirrelVersion $squirrelVersion
        Pass "licenses/UPSTREAM.tsv parses and is pinned to build.ps1's Squirrel.Windows $squirrelVersion"
    } catch {
        Fail "licenses/UPSTREAM.tsv does not parse for Squirrel.Windows $squirrelVersion" "$_"
    }
    if ($entries) {
        # The components build.ps1 takes from its own inputs instead (see Install-BundleLicenses)
        $fromBuild = @("squirrel-windows", "semver", "7-zip", "nuget-commandline")
        $listed = Get-Content $manifest | Where-Object { $_ -notmatch '^\s*(#|$)' } | ForEach-Object { ($_ -split "`t")[1] } | Sort-Object -Unique
        $fetched = $entries | ForEach-Object { $_.Component } | Sort-Object -Unique
        $uncovered = $listed | Where-Object { $_ -notin $fetched -and $_ -notin $fromBuild }
        $unused = $fetched | Where-Object { $_ -notin $listed }
        if ($uncovered) { Fail "every MANIFEST.tsv component has license files" "not in UPSTREAM.tsv nor taken from the build: $($uncovered -join ', ')" }
        else { Pass "every MANIFEST.tsv component has license files (UPSTREAM.tsv or the build inputs)" }
        if ($unused) { Fail "every UPSTREAM.tsv component is used" "not in MANIFEST.tsv: $($unused -join ', ')" }
        else { Pass "every UPSTREAM.tsv component is listed in MANIFEST.tsv" }
        $hosts = $entries | ForEach-Object { ([uri]$_.Url).Host } | Sort-Object -Unique
        $unexpected = $hosts | Where-Object { $_ -notin @("raw.githubusercontent.com", "api.nuget.org", "downloads.sourceforge.net") }
        if ($unexpected) { Fail "UPSTREAM.tsv downloads only from GitHub raw, nuget.org and SourceForge" ($unexpected -join ", ") }
        else { Pass "UPSTREAM.tsv downloads only from $($hosts -join ', ')" }
        $floating = $entries | Where-Object { $_.Url -match '/(master|main|HEAD|latest)/' }
        if ($floating) { Fail "UPSTREAM.tsv pins every URL" ($floating.Url -join "`n") }
        else { Pass "UPSTREAM.tsv names no branch (master, main, HEAD, latest) in a URL" }
    }

    if ($Live) {
        $liveDir = Join-Path $work "live"
        $out = & $pwsh -NoProfile -NonInteractive -Command "`$ErrorActionPreference = 'Stop'; . '$helpers'; Install-UpstreamLicenses -Manifest '$upstream' -LicensesDir '$liveDir' -WorkDir '$liveDir.downloads' -SquirrelVersion '$squirrelVersion'" 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Pass "-Live: every file in UPSTREAM.tsv downloads and matches its SHA-256"; Write-Host $out }
        else { Fail "-Live: downloading UPSTREAM.tsv failed (exit $LASTEXITCODE)" $out }
    }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures -gt 0) {
    Write-Host "❌ $($script:failures) upstream license test(s) failed"
    exit 1
}
Write-Host "✓ All upstream license tests passed"
