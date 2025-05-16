const path = require("path");
const fs = require("fs");
const { execSync } = require("child_process");

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
  if (!process.env.DRY_RUN) {
    fs.rmSync(artifactDestination, { recursive: true, force: true });
    fs.renameSync(stagingArtifactPath, artifactDestination);
    console.log(`Moved ${stagingArtifactPath} to ${artifactDestination}...`);

    execSync(`git add --force -A ${artifactDestination}`);
    console.log(`Committed ${artifactDestination}...`);
  } else {
    console.log(`DRY_RUN: Verified ${artifactDestination}...`);
  }
});

if (!process.env.DRY_RUN) {
  // Remove the changeset status file
  fs.rmSync(stagingDir, { recursive: true, force: true });
  console.log(`Removed ${stagingDir}...`);
}