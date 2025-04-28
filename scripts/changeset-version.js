const path = require("path")
const fs = require("fs")
const { execSync } = require("child_process")
const os = require("os")

// const { version } = require("../package.json")
// const { GITHUB_REF, GITHUB_SHA } = process.env

// changeset status outputs at __dirname even if we set absolute output path
const changesetJsonPath = "changeset-status.json"

execSync(`pnpm changeset status --output ${changesetJsonPath}`)

const changesetJson = JSON.parse(fs.readFileSync(changesetJsonPath, "utf-8"))
const releases = changesetJson.releases

console.log("Releases:", releases)