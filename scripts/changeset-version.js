const path = require("path");
const fs = require("fs");
const { execSync } = require("child_process");
const packageMap = require("./changeset-packagemap");

// changeset status expects relative __dirname even if we set absolute output path
const changesetJsonPath = "changeset-status.json";

execSync(`pnpm changeset status --output ${changesetJsonPath}`);

const changesetJson = JSON.parse(fs.readFileSync(changesetJsonPath, "utf-8"));
const releases = changesetJson.releases;

console.log("Release candidates:", releases);

releases.forEach((release) => {
  const { name } = release;
  const artifactsToUpload = packageMap[name];
  if (!artifactsToUpload) {
    throw new Error(`No artifacts found for ${name}`);
  }
  console.log(`Committing artifacts for ${name}...`);
  artifactsToUpload.forEach((artifact) => {
    const artifactPath = path.resolve(__dirname, "../artifacts", artifact);
    if (!fs.existsSync(artifactPath)) {
      throw new Error(`Artifact not found: ${artifactPath}. Please check the package<=>file map in 'changeset-packagemap.js'`);
    }
    // --force because the folder is ignored by git to prevent accidental commits
    execSync(`git add --force ${artifactPath}`);
  });
});
