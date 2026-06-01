const path = require("path");
const fs = require("fs");
const { execSync } = require("child_process");

const isDryRun = process.env.DRY_RUN || process.argv.includes("--dry-run");

// changeset status expects relative __dirname even if we set absolute output path
const changesetJsonPath = "changeset-status.json";

execSync(`pnpm changeset status --output ${changesetJsonPath}`);

const changesetJson = JSON.parse(fs.readFileSync(changesetJsonPath, "utf-8"));
const releases = changesetJson.releases;

console.log("Release candidates:", releases);
const stagingDir = path.resolve(__dirname, "../artifacts-staging");

releases.forEach((release) => {
  const { name } = release;
  const artifactDestination = path.resolve(__dirname, "../artifacts", name);
  const stagingArtifactPath = path.resolve(stagingDir, name);
  if (!isDryRun) {
    fs.rmSync(artifactDestination, { recursive: true, force: true });
    fs.renameSync(stagingArtifactPath, artifactDestination);
    console.log(`Moved ${stagingArtifactPath} to ${artifactDestination}...`);

    execSync(`git add --force -A ${artifactDestination}`);
    console.log(`Committed ${artifactDestination}...`);
  } else {
    if (fs.existsSync(stagingArtifactPath)) {
      if (!fs.statSync(stagingArtifactPath).isDirectory()) {
        console.error(`DRY_RUN ERROR: ${stagingArtifactPath} exists but is not a directory — artifact structure is wrong`);
        process.exit(1);
      }
      console.log(`DRY_RUN: Verified ${stagingArtifactPath} exists as a directory.`);
    } else {
      console.log(`DRY_RUN: ${stagingArtifactPath} not present (no artifacts built for ${name}).`);
    }
  }
});

if (!isDryRun) {
  // Remove the changeset status file
  fs.rmSync(stagingDir, { recursive: true, force: true });
  console.log(`Removed ${stagingDir}...`);
}