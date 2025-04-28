const path = require("path");
const fs = require("fs");
const { execSync } = require("child_process");
const os = require("os");

// const { version } = require("../package.json")
// const { GITHUB_REF, GITHUB_SHA } = process.env

// changeset status outputs at __dirname even if we set absolute output path
const changesetJsonPath = "changeset-status.json";

execSync(`pnpm changeset status --output ${changesetJsonPath}`);

const changesetJson = JSON.parse(fs.readFileSync(changesetJsonPath, "utf-8"));
const releases = changesetJson.releases;

console.log("Releases:", releases);

const packageMap = {
  appimage: ["appimage-13.0.1.7z"],
  nsis: ["nsis-3.0.5.0.7z"],
  "nsis-resources": ["nsis-resources-3.4.1.7z"],
  ran: ["ran-0.1.3.7z"],
  "squirrel.windows": ["Squirrel.Windows-1.9.0.7z"],
  "win-codesign": ["winCodeSign-2.6.0.7z"],
  wine: ["wine-4.0.1-mac.7z"],
  wix: ["wix-4.0.0.5512.2.7z"],
  zstd: [
    "zstd-v1.5.5-linux-x64.7z",
    "zstd-v1.5.5-mac.7z",
    "zstd-v1.5.5-win-ia32.7z",
    "zstd-v1.5.5-win-x64.7z",
  ],
  fpm: [
    "fpm-1.9.3-2.3.1-linux-x86_64.7z",
    "fpm-1.9.3-2.3.1-linux-x86.7z",
    "fpm-1.9.3-20150715-2.2.2-mac.7z",
  ],
  "linux-tools": ["linux-tools-mac-10.12.4.7z"],
  "snap-template": [
    "snap-template-electron-4.0-1-amd64.tar.7z",
    "snap-template-electron-4.0-1-armhf.tar.7z",
    "snap-template-electron-4.0-2-amd64.tar.7z",
    "snap-template-electron-4.0.tar.7z",
  ],
};

releases.forEach((release) => {
  const { name } = release;
  const artifactsToUpload = packageMap[name];
  if (!artifactsToUpload) {
    console.warn(`No artifacts found for ${name}`);
    return;
  }
  console.log(`Committing artifacts for ${name}...`);
  artifactsToUpload.forEach((artifact) => {
    const artifactPath = path.resolve(__dirname, "../artifacts", artifact);
    // --force because the folder is ignored by git to prevent accidental commits
    execSync(`git add --force ${artifactPath}`);
  });
});
