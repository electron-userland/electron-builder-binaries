#!/usr/bin/env node
// Checks the Renovate customManagers in .github/renovate.json5 against the repository:
//   - every "# renovate:" annotation is picked up by exactly one regex manager and yields a datasource, a depName
//     and a version-like currentValue (an annotation that silently matches nothing would never be updated)
//   - every customManager extracts at least one dependency
//   - the regexes stay RE2-compatible (Renovate runs them with RE2: no lookaround, no backreferences)
//   - the annotation regexes extract the right value from each line format used in the repo (fixtures below)
//
// Usage (the config is JSON5, so it is converted first):
//   pnpm --silent dlx json5@2.2.3 .github/renovate.json5 | node scripts/tests/renovate-annotations-test.mjs
//   node scripts/tests/renovate-annotations-test.mjs <config.json>

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const CONFIG_PATH = ".github/renovate.json5";
const ANNOTATION = /^[ \t]*# renovate:/;

let failures = 0;
const fail = (msg) => {
  failures++;
  console.error(`  ❌ ${msg}`);
};

const raw = readFileSync(process.argv[2] ?? 0, "utf8");
let config;
try {
  config = JSON.parse(raw);
} catch (e) {
  console.error(`❌ Could not parse the Renovate config as JSON (convert ${CONFIG_PATH} with the json5 CLI first): ${e.message}`);
  process.exit(1);
}

const managers = (config.customManagers ?? []).filter((m) => m.customType === "regex");
if (managers.length === 0) {
  console.error("❌ No regex customManagers in the config");
  process.exit(1);
}

// managerFilePatterns: only the /regex/ form is used here
const filePatterns = (m) =>
  (m.managerFilePatterns ?? []).map((p) => {
    const re = /^\/(.*)\/([a-z]*)$/s.exec(p);
    if (!re) throw new Error(`managerFilePatterns entry is not a /regex/: ${p} (this test only supports the regex form)`);
    return new RegExp(re[1], re[2]);
  });

const lineOf = (text, index) => text.slice(0, index).split("\n").length;

// Applies a manager's matchStrings like Renovate's regex manager (strategy "any"): every match of every matchString.
function extract(manager, text) {
  const deps = [];
  for (const source of manager.matchStrings) {
    for (const m of text.matchAll(new RegExp(source, "g"))) {
      const g = m.groups ?? {};
      deps.push({
        line: lineOf(text, m.index),
        datasource: g.datasource ?? manager.datasourceTemplate,
        depName: g.depName ?? manager.depNameTemplate,
        currentValue: g.currentValue ?? manager.currentValueTemplate,
        currentDigest: g.currentDigest,
        match: m[0],
      });
    }
  }
  return deps;
}

console.log("🧪 Renovate customManagers");

// ── RE2 compatibility ────────────────────────────────────────────────────────────
console.log("\n── RE2-compatible regexes ──");
const RE2_UNSUPPORTED = [
  [/\(\?[=!]/, "lookahead"],
  [/\(\?<[=!]/, "lookbehind"],
  [/\\[1-9]/, "numbered backreference"],
  [/\\k</, "named backreference"],
];
for (const [i, m] of managers.entries()) {
  for (const s of m.matchStrings ?? []) {
    for (const [re, what] of RE2_UNSUPPORTED) {
      if (re.test(s)) fail(`customManagers[${i}] uses a ${what}, which RE2 does not support: ${s}`);
    }
    try {
      new RegExp(s, "g");
    } catch (e) {
      fail(`customManagers[${i}] matchString does not compile: ${e.message}`);
    }
  }
}
if (failures === 0) console.log("  ✓ no lookaround or backreferences");

// ── Line formats ──────────────────────────────────────────────────────────────────
// [annotation (after "# renovate: "), line, expected currentValue, expected currentDigest]
console.log("\n── Line formats ──");
const SHA = "a4ba28e60bd9e7c271cd2bfc1558889ce3355653";
const FIXTURES = [
  ["datasource=github-releases depName=o/r", 'X="${X:-26.05}"', "26.05"],
  ["datasource=github-tags depName=o/r", 'X=${X:-"4.7.5"}', "4.7.5"],
  ["datasource=github-tags depName=o/r", "X=${X:-v313}", "v313"],
  ["datasource=github-releases depName=o/r", 'export X="20251108"', "20251108"],
  ["datasource=ruby-version depName=ruby", "export RUBY_VERSION=3.4.12", "3.4.12"],
  ["datasource=github-tags depName=o/r", "ARG X=2.14", "2.14"],
  ["datasource=gitlab-tags depName=o/r registryUrl=https://gitlab.example.org", 'ARG X="0.28"', "0.28"],
  ["datasource=github-releases depName=o/r", '        default: "26.05"', "26.05"],
  ["datasource=github-releases depName=o/r", "          X: ${{ inputs.x || '2.0.0' }}", "2.0.0"],
  ["datasource=rubygems depName=fpm", 'GEM_LIST=("fpm -v 1.18.0" "ruby-xz") # comment', "1.18.0"],
  ["datasource=pypi depName=pytest", '    --target "$DIR" "pytest==9.2.0"', "9.2.0"],
  ["datasource=github-releases depName=m3ng9i/ran", 'VERSION="v0.1.6" bash "$ROOT/assets/build.sh"', "v0.1.6"],
  ["datasource=github-tags depName=o/r", '    [string]$SquirrelVersion = "2.0.1",', "2.0.1"],
  ["datasource=nuget depName=NuGet.CommandLine", '$nugetVersion       = "7.9.0"', "7.9.0"],
  ["datasource=nuget depName=X", "nuget install X -Version 1.0.3 `", "1.0.3"],
  ["datasource=docker depName=ubuntu", "FROM ubuntu:22.04 AS builder", "22.04"],
  ["datasource=github-releases depName=o/r", '    "https://github.com/o/r/releases/download/v1.0.5.7/INetC.zip"', "v1.0.5.7"],
  ["datasource=github-releases depName=o/r", '    "P|https://raw.githubusercontent.com/o/r/1.14/LGPL.txt|abc|LGPL.txt"', "1.14"],
  [
    "datasource=gitlab-tags depName=wine/wine extractVersion=^wine-(?<version>\\d+\\.0(\\.\\d+)?)$ registryUrl=https://gitlab.example.org",
    "WINE_VERSION=${WINE_VERSION:-11.0}",
    "11.0",
  ],
  [
    "datasource=github-tags depName=o/r versioning=regex:^v(?<major>\\d)(?<minor>\\d{2})(?<patch>\\d)?$",
    "NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v313}",
    "v313",
  ],
  ["datasource=github-tags depName=o/r currentValue=v313", `export X="${SHA}" # v3.13 stable release`, "v313", SHA],
  ["datasource=github-tags depName=o/r currentValue=4.7.5", `X=\${X:-"${SHA}"}`, "4.7.5", SHA],
];
const annotationManagers = managers.filter((m) => m.matchStrings.some((s) => s.startsWith("# renovate: ")));
for (const [annotation, line, value, digest] of FIXTURES) {
  const text = `# renovate: ${annotation}\n${line}\n`;
  const deps = annotationManagers.flatMap((m) => extract(m, text));
  const label = `${line.trim()}`;
  if (deps.length !== 1) {
    fail(`${label}: ${deps.length} matches, expected 1`);
  } else if (deps[0].currentValue !== value || deps[0].currentDigest !== digest) {
    fail(`${label}: currentValue=${deps[0].currentValue} currentDigest=${deps[0].currentDigest}, expected ${value} ${digest ?? ""}`);
  } else {
    console.log(`  ✓ ${label} → ${value}${digest ? ` @ ${digest.slice(0, 7)}` : ""}`);
  }
}
// An annotation that is not directly above the version must not match anything
for (const text of ["# renovate: datasource=pypi depName=x\n\nX=1.0.0\n", "# renovate: depName=x datasource=pypi\nX=1.0.0\n"]) {
  const deps = annotationManagers.flatMap((m) => extract(m, text));
  if (deps.length !== 0) fail(`a malformed annotation matched: ${JSON.stringify(text)}`);
  else console.log(`  ✓ no match for malformed annotation ${JSON.stringify(text.split("\n")[0])}${text.includes("\n\n") ? " + blank line" : ""}`);
}

// ── Repository ─────────────────────────────────────────────────────────────────
console.log("\n── Repository annotations ──");
const files = execFileSync("git", ["ls-files", "-z"], { cwd: ROOT, encoding: "utf8" })
  .split("\0")
  .filter(Boolean)
  .filter((f) => f !== CONFIG_PATH && !f.startsWith("artifacts/") && f !== "scripts/tests/renovate-annotations-test.mjs");

const depsByFile = new Map(); // file -> deps
const perManager = managers.map(() => 0);
for (const [i, m] of managers.entries()) {
  const patterns = filePatterns(m);
  for (const f of files) {
    if (!patterns.some((p) => p.test(f))) continue;
    const deps = extract(m, readFileSync(join(ROOT, f), "utf8"));
    perManager[i] += deps.length;
    for (const d of deps) {
      d.manager = i;
      if (!depsByFile.has(f)) depsByFile.set(f, []);
      depsByFile.get(f).push(d);
    }
  }
}

let annotations = 0;
const summary = new Map();
for (const f of files) {
  let text;
  try {
    text = readFileSync(join(ROOT, f), "utf8");
  } catch {
    continue;
  }
  if (!text.includes("# renovate:")) continue;
  const lines = text.split("\n");
  lines.forEach((l, idx) => {
    if (!ANNOTATION.test(l)) return;
    annotations++;
    const where = `${f}:${idx + 1}`;
    const hits = (depsByFile.get(f) ?? []).filter((d) => d.line === idx + 1);
    if (hits.length === 0) {
      fail(`${where}: annotation is not matched by any customManager (key order, file pattern or the line below?)\n       ${l.trim()}\n       ${(lines[idx + 1] ?? "").trim()}`);
      return;
    }
    if (hits.length > 1) {
      fail(`${where}: annotation is matched ${hits.length} times (managers ${hits.map((h) => h.manager).join(", ")})`);
      return;
    }
    const [d] = hits;
    if (!d.datasource || !d.depName) fail(`${where}: no datasource / depName extracted`);
    if (!d.currentValue || !/\d/.test(d.currentValue)) fail(`${where}: currentValue "${d.currentValue}" does not look like a version`);
    if (d.currentDigest !== undefined && !/^[0-9a-f]{40}$/.test(d.currentDigest)) fail(`${where}: currentDigest "${d.currentDigest}" is not a commit`);
    const key = `${d.datasource} ${d.depName}`;
    const s = summary.get(key) ?? { values: new Set(), count: 0 };
    s.values.add(d.currentDigest ? `${d.currentValue}@${d.currentDigest.slice(0, 7)}` : d.currentValue);
    s.count++;
    summary.set(key, s);
  });
}
for (const [key, s] of [...summary].sort()) {
  console.log(`  ✓ ${key} = ${[...s.values].join(", ")} (${s.count}×)`);
}

console.log("\n── Every customManager extracts something ──");
for (const [i, m] of managers.entries()) {
  if (perManager[i] === 0) fail(`customManagers[${i}] (${m.description ?? m.matchStrings[0]}) matches nothing in the repository`);
  else console.log(`  ✓ customManagers[${i}]: ${perManager[i]} dependencies`);
}

console.log("");
if (annotations === 0) fail("no # renovate: annotations found");
if (failures > 0) {
  console.error(`❌ ${failures} failure(s)`);
  process.exit(1);
}
console.log(`✅ ${annotations} annotations, ${summary.size} upstream dependencies, all extracted`);
