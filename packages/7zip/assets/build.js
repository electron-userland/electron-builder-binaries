#!/usr/bin/env node
"use strict";
/**
 * 7-Zip inner build script — runs inside node:lts-bookworm-slim Docker container.
 *
 * Bundle layout (after tar.extract with strip:1):
 *   bin/7zz          ← original upstream binary  (linux / darwin)
 *   bin/7za → 7zz   ← symlink entrypoint          (linux / darwin)
 *   bin/7za.exe      ← original upstream binary  (windows)
 *   bin/7za.ps1      ← PowerShell entrypoint      (windows)
 *   LICENSE.txt
 *   COPYING
 *
 * Usage: node build.js --version VERSION [--output-dir DIR] [--work-dir DIR] [--target TARGET]
 */

const { execSync } = require("child_process");
const { copyFileSync, chmodSync, existsSync, mkdirSync, rmSync, symlinkSync, writeFileSync, readFileSync, readdirSync } = require("fs");
const { basename, join } = require("path");
const { createHash } = require("crypto");

// ─── Argument parsing ─────────────────────────────────────────────────────────

let version = process.env.SEVEN_ZIP_VERSION || "";
let outputDir = "/output";
let workDir = "/build/7zip-work";
let target = "all";
let printDownloadsChecksum = false;

for (let i = 2; i < process.argv.length; i++) {
  switch (process.argv[i]) {
    case "--version":
      version = process.argv[++i];
      break;
    case "--output-dir":
      outputDir = process.argv[++i];
      break;
    case "--work-dir":
      workDir = process.argv[++i];
      break;
    case "--target":
      target = process.argv[++i];
      break;
    case "--print-downloads-checksum":
      printDownloadsChecksum = true;
      break;
    case "--help":
    case "-h":
      console.log("Usage: node build.js --version VERSION [--output-dir DIR] [--work-dir DIR] [--target all|linux|darwin|win] [--print-downloads-checksum]");
      process.exit(0);
    default:
      console.error(`❌ Unknown option: ${process.argv[i]}`);
      process.exit(1);
  }
}

if (!version) {
  console.error("❌ --version is required (e.g. --version 24.09)");
  process.exit(1);
}

const ver = version.replace(/\./g, ""); // "24.09" → "2409"
const base = `https://github.com/ip7z/7zip/releases/download/${version}`;

// ─── SHA-256 manifest ─────────────────────────────────────────────────────────

const SRC_SHA256 = "49c05169f49572c1128453579af1632a952409ced028259381dac30726b6133a"; // 7z-src.tar.xz
const LX64_SHA256 = "914c7e20ad5ef8e4d3cf08620ff8894b28fe11b7eb99809d6930870fbe48a281"; // linux-x64.tar.xz
const LARM64_SHA256 = "fbe331697c9417bbc06fc92d3f4576dca6a5a1442fad7ae810304446a9153e2c"; // linux-arm64.tar.xz
const LIA32_SHA256 = "cb5e49caaf761df67add54729553bef89a38071b0c455461452578018625fee5"; // linux-ia32.tar.xz
const MAC_SHA256 = "073b6fa8dc5d9adb6f742888d0d75f5767406b503199b9704ccbf61133a21ded"; // mac.tar.xz
const WX64_SHA256 = "43ae97658d0fc5b4eec4d409d85f7bed74a80945fd5704333a3599e0bd79b5fc"; // extra.7z
const WARM64_SHA256 = "bc7b3a18f218f4916e1c4996751468f96e46eb7e97e91e8c1553d74793037f1a"; // win-arm64-installer.exe
const WIA32_SHA256 = "e35e4374100b52e697e002859aefdd5533bcbf4118e5d2210fae6de318947c41"; // win-ia32-installer.exe

// ─── Helpers ──────────────────────────────────────────────────────────────────

const sh = (cmd) => execSync(cmd, { stdio: "inherit" });
const quiet = (cmd) => execSync(cmd, { stdio: "ignore" });
const stdout = (cmd) => execSync(cmd).toString().trim();

function download(url, dest) {
  console.log(`  📥 ${basename(dest)} ← ${url}`);
  quiet(`curl -fsSL --retry 3 --retry-delay 2 --max-time 300 ${q(url)} -o ${q(dest)}`);
}

function q(s) {
  return JSON.stringify(s);
} // shell-safe quoting

function verifySha256(file, expected) {
  if (!expected) return;
  const actual = createHash("sha256").update(readFileSync(file)).digest("hex");
  if (actual !== expected) {
    console.error(`❌ SHA-256 mismatch for ${basename(file)}\n   expected: ${expected}\n   actual:   ${actual}`);
    process.exit(1);
  }
  console.log(`  ✓ SHA-256 ok: ${basename(file)}`);
}

// Tracks every upstream file that was downloaded so --print-downloads-checksum
// can emit ready-to-paste const declarations at the end of the run.
const downloadedFiles = new Map(); // constName → localFilePath

function trackDownload(constName, filePath) {
  downloadedFiles.set(constName, filePath);
}

function printDownloadChecksums() {
  console.log("\n── Upstream download checksums ──────────────────────────────");
  console.log("// Paste into the SHA-256 manifest at the top of build.js:");
  for (const [name, file] of downloadedFiles) {
    if (!existsSync(file)) continue;
    const sha = createHash("sha256").update(readFileSync(file)).digest("hex");
    console.log(`const ${name.padEnd(15)} = "${sha}"; // ${basename(file)}`);
  }
}

function copyLicenses(destDir) {
  copyFileSync(join(workDir, "LICENSE.txt"), join(destDir, "LICENSE.txt"));
  copyFileSync(join(workDir, "COPYING"), join(destDir, "COPYING"));
}

function bundleUnix(name, binaryPath) {
  const bundleBase = join(workDir, `bundle_${name}`);
  const binDir = join(bundleBase, "7zip", "bin");
  rmSync(bundleBase, { recursive: true, force: true });
  mkdirSync(binDir, { recursive: true });

  const binName = basename(binaryPath);
  copyFileSync(binaryPath, join(binDir, binName));
  chmodSync(join(binDir, binName), 0o755);
  symlinkSync(binName, join(binDir, "7za")); // stable entrypoint → original binary

  copyLicenses(join(bundleBase, "7zip"));
  quiet(`tar -czf ${q(join(outputDir, `${name}.tar.gz`))} -C ${q(bundleBase)} 7zip`);
  console.log(`  ✅ ${name}.tar.gz  (${binName} + 7za → ${binName})`);
}

function bundleWin(name, binaryPath) {
  const bundleBase = join(workDir, `bundle_${name}`);
  const binDir = join(bundleBase, "7zip", "bin");
  rmSync(bundleBase, { recursive: true, force: true });
  mkdirSync(binDir, { recursive: true });

  copyFileSync(binaryPath, join(binDir, "7za.exe"));
  writeFileSync(join(binDir, "7za.ps1"), '& "$PSScriptRoot\\7za.exe" @args\nexit $LASTEXITCODE\n');

  copyLicenses(join(bundleBase, "7zip"));
  quiet(`tar -czf ${q(join(outputDir, `${name}.tar.gz`))} -C ${q(bundleBase)} 7zip`);
  console.log(`  ✅ ${name}.tar.gz  (7za.exe + 7za.ps1)`);
}

// Extract a NSIS installer (self-extracting 7z archive) and return the path to
// 7za.exe inside it, or null if not present.
function extractNsis(installer, dest) {
  mkdirSync(dest, { recursive: true });
  quiet(`7zz x -bd ${q(installer)} -o${q(dest)} -y`);
  const found = stdout(`find ${q(dest)} -name "7za.exe" -print -quit 2>/dev/null`);
  return found || null;
}

// ─── License fetch ────────────────────────────────────────────────────────────

function fetchLicenses() {
  console.log("\n── License ──────────────────────────────────────────────────");
  const srcArchive = join(workDir, "7z-src.tar.xz");
  const srcExtract = join(workDir, "src-extract");

  download(`${base}/7z${ver}-src.tar.xz`, srcArchive);
  trackDownload("SRC_SHA256", srcArchive);
  verifySha256(srcArchive, SRC_SHA256);

  mkdirSync(srcExtract, { recursive: true });
  console.log("  Extracting license files from source tarball...");

  // 7-Zip source layout varies between releases — try DOC/ then root
  try {
    quiet(`tar -xJf ${q(srcArchive)} -C ${q(srcExtract)} --strip-components=1 --wildcards "*/DOC/License.txt" "*/DOC/copying.txt"`);
  } catch {
    quiet(`tar -xJf ${q(srcArchive)} -C ${q(srcExtract)} --strip-components=1 --wildcards "*/License.txt" "*/copying.txt"`);
  }

  const pick = (pattern, dest) => {
    const hit = stdout(`find ${q(srcExtract)} -iname ${q(pattern)} -print -quit 2>/dev/null`);
    if (hit) copyFileSync(hit, join(workDir, dest));
  };
  pick("license.txt", "LICENSE.txt");
  pick("copying.txt", "COPYING");
  pick("copying", "COPYING"); // some releases name it without extension

  if (!existsSync(join(workDir, "LICENSE.txt"))) download("https://www.7-zip.org/license.txt", join(workDir, "LICENSE.txt"));
  if (!existsSync(join(workDir, "COPYING"))) copyFileSync(join(workDir, "LICENSE.txt"), join(workDir, "COPYING"));

  if (!existsSync(join(workDir, "LICENSE.txt")) || !existsSync(join(workDir, "COPYING"))) {
    console.error("❌ License files not found — cannot proceed");
    process.exit(1);
  }
  console.log("  License files ready.");
}

// ─── Linux ────────────────────────────────────────────────────────────────────

function buildLinux() {
  console.log("\n── Linux ────────────────────────────────────────────────────");
  if (!LX64_SHA256 && !LARM64_SHA256 && !LIA32_SHA256) console.log("  ⚠️  SHA-256 not yet configured — fill in the manifest at the top of this file.");

  const lx64 = join(workDir, "linux-x64.tar.xz");
  const larm64 = join(workDir, "linux-arm64.tar.xz");
  const lia32 = join(workDir, "linux-ia32.tar.xz");

  download(`${base}/7z${ver}-linux-x64.tar.xz`, lx64);
  trackDownload("LX64_SHA256", lx64);
  verifySha256(lx64, LX64_SHA256);
  download(`${base}/7z${ver}-linux-arm64.tar.xz`, larm64);
  trackDownload("LARM64_SHA256", larm64);
  verifySha256(larm64, LARM64_SHA256);
  download(`${base}/7z${ver}-linux-x86.tar.xz`, lia32);
  trackDownload("LIA32_SHA256", lia32);
  verifySha256(lia32, LIA32_SHA256);

  bundleLinuxArch("linux-x64", lx64);
  bundleLinuxArch("linux-arm64", larm64);
  bundleLinuxArch("linux-ia32", lia32);
}

function bundleLinuxArch(name, archive) {
  const dir = join(workDir, `extract-${name}`);
  mkdirSync(dir, { recursive: true });
  quiet(`tar -xJf ${q(archive)} -C ${q(dir)}`);
  const bin = join(dir, "7zz");
  if (!existsSync(bin)) {
    console.error(`❌ 7zz not found in ${name} archive`);
    process.exit(1);
  }
  bundleUnix(`7zip-${name}`, bin);
}

// ─── macOS ───────────────────────────────────────────────────────────────────

function buildDarwin() {
  console.log("\n── macOS ────────────────────────────────────────────────────");
  if (!MAC_SHA256) console.log("  ⚠️  SHA-256 not yet configured — fill in the manifest at the top of this file.");

  const macArchive = join(workDir, "mac.tar.xz");
  download(`${base}/7z${ver}-mac.tar.xz`, macArchive);
  trackDownload("MAC_SHA256", macArchive);
  verifySha256(macArchive, MAC_SHA256);

  const macExtract = join(workDir, "extract-mac");
  mkdirSync(macExtract, { recursive: true });
  quiet(`tar -xJf ${q(macArchive)} -C ${q(macExtract)}`);

  const bin = join(macExtract, "7zz");
  if (!existsSync(bin)) {
    console.error("❌ 7zz not found in macOS archive");
    process.exit(1);
  }

  // Universal binary (arm64 + x86_64) — one download, two bundles
  bundleUnix("7zip-darwin-arm64", bin);
  bundleUnix("7zip-darwin-x86_64", bin);
}

// ─── Windows ─────────────────────────────────────────────────────────────────

function buildWin() {
  console.log("\n── Windows ──────────────────────────────────────────────────");
  if (!WX64_SHA256 && !WARM64_SHA256 && !WIA32_SHA256) console.log("  ⚠️  SHA-256 not yet configured — fill in the manifest at the top of this file.");

  // x64: standalone 7za.exe ships in the "extra" package
  const extraArchive = join(workDir, "extra.7z");
  const winX64Extract = join(workDir, "extract-win-x64");
  download(`${base}/7z${ver}-extra.7z`, extraArchive);
  trackDownload("WX64_SHA256", extraArchive);
  verifySha256(extraArchive, WX64_SHA256);
  mkdirSync(winX64Extract, { recursive: true });
  quiet(`7zz x -bd ${q(extraArchive)} -o${q(winX64Extract)} -y`);
  // The "extra" package roots the 32-bit x86 console build; the 64-bit and
  // ARM64 console builds live in its x64/ and arm64/ subdirectories. Bundling
  // the root binary shipped a 32-bit 7za as 7zip-win-x64, which caps 7-Zip's
  // compression memory budget at 80% of 1.75 GiB and quietly collapses LZMA2
  // multithreading to ~1 encoder (see electron-builder-binaries#222).
  const winX64Exe = join(winX64Extract, "x64", "7za.exe");
  if (!existsSync(winX64Exe)) {
    console.error("❌ x64/7za.exe not found in extra.7z");
    process.exit(1);
  }
  bundleWin("7zip-win-x64", winX64Exe);
  // The root of the extra package IS the 32-bit x86 build — the right
  // fallback for ia32 (and never for x64/arm64).
  const winIa32ExtraExe = join(winX64Extract, "7za.exe");
  // Native ARM64 console build from the same extra package.
  const winArm64ExtraExe = join(winX64Extract, "arm64", "7za.exe");

  // arm64: NSIS installer; fall back to x64 binary if 7za.exe not bundled
  const arm64Installer = join(workDir, "win-arm64-installer.exe");
  download(`${base}/7z${ver}-arm64.exe`, arm64Installer);
  trackDownload("WARM64_SHA256", arm64Installer);
  verifySha256(arm64Installer, WARM64_SHA256);
  const arm64Exe = extractNsis(arm64Installer, join(workDir, "extract-win-arm64"));
  if (arm64Exe) console.log(`  Found 7za.exe (arm64): ${arm64Exe}`);
  else console.log("  ⚠️  7za.exe not found in arm64 installer — falling back to x64");
  bundleWin("7zip-win-arm64", existsSync(winArm64ExtraExe) ? winArm64ExtraExe : (arm64Exe ?? winX64Exe));

  // ia32: NSIS installer; fall back to x64 binary if 7za.exe not bundled
  const ia32Installer = join(workDir, "win-ia32-installer.exe");
  download(`${base}/7z${ver}.exe`, ia32Installer);
  trackDownload("WIA32_SHA256", ia32Installer);
  verifySha256(ia32Installer, WIA32_SHA256);
  const ia32Exe = extractNsis(ia32Installer, join(workDir, "extract-win-ia32"));
  if (ia32Exe) console.log(`  Found 7za.exe (ia32): ${ia32Exe}`);
  else console.log("  ⚠️  7za.exe not found in ia32 installer — falling back to x64");
  bundleWin("7zip-win-ia32", ia32Exe ?? winIa32ExtraExe);
}

// ─── Checksums ────────────────────────────────────────────────────────────────

function writeChecksums() {
  console.log("\n── Checksums ────────────────────────────────────────────────");
  const archives = readdirSync(outputDir).filter((f) => f.endsWith(".tar.gz"));
  for (const f of archives) {
    const fullPath = join(outputDir, f);
    const sha = createHash("sha256").update(readFileSync(fullPath)).digest("hex");
    const entry = `${sha}  ${f}`;
    console.log(entry);
    writeFileSync(join(outputDir, f.replace(/\.tar\.gz$/, ".sha256")), entry + "\n");
  }
}

// ─── Bootstrap ────────────────────────────────────────────────────────────────

console.log("📦 Installing build dependencies...");
execSync("apt-get update -qq", { stdio: "ignore" });
execSync("apt-get install -y --no-install-recommends curl ca-certificates xz-utils 7zip", { stdio: "ignore" });

mkdirSync(workDir, { recursive: true });
mkdirSync(outputDir, { recursive: true });

const bar = "━".repeat(54);
console.log(`\n${bar}\n🏗️  7-Zip ${version} — target: ${target}\n${bar}`);

// ─── Dispatch ─────────────────────────────────────────────────────────────────

fetchLicenses();

switch (target) {
  case "all":
    buildLinux();
    buildDarwin();
    buildWin();
    break;
  case "linux":
    buildLinux();
    break;
  case "darwin":
    buildDarwin();
    break;
  case "win":
    buildWin();
    break;
  default:
    console.error(`❌ Unknown target: ${target}`);
    process.exit(1);
}

writeChecksums();

if (printDownloadsChecksum) printDownloadChecksums();

console.log(`\n${bar}`);
console.log(`✅  7-Zip ${version} — ${target} bundles complete`);
console.log(bar);
sh(`ls -lh ${q(outputDir)}/*.tar.gz`);
