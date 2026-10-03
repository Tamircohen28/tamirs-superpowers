#!/usr/bin/env node
/**
 * check-no-agent-drift.mjs — verify thin adapters reference AGENTS.md (Node repos).
 * Copy to target repo scripts/ during dev mode Phase 4.
 */
import fs from "node:fs";
import path from "node:path";

const root = process.argv[2] || ".";
let failed = false;

function err(msg) {
  console.error(`ERROR: ${msg}`);
  failed = true;
}

const agents = path.join(root, "AGENTS.md");
if (!fs.existsSync(agents)) {
  err("AGENTS.md missing at repo root");
}

const claude = path.join(root, "CLAUDE.md");
if (fs.existsSync(claude)) {
  const body = fs.readFileSync(claude, "utf8");
  if (!body.includes("AGENTS.md")) {
    err("CLAUDE.md must reference AGENTS.md (prefer @AGENTS.md on line 1)");
  }
}

const rulesDir = path.join(root, ".cursor", "rules");
if (fs.existsSync(rulesDir)) {
  const files = fs.readdirSync(rulesDir);
  if (files.some((f) => f.endsWith(".md") && !f.endsWith(".mdc"))) {
    err(".cursor/rules/ contains .md files — rename to .mdc");
  }
  const mdc = files.filter((f) => f.endsWith(".mdc"));
  if (mdc.length && !mdc.some((f) => fs.readFileSync(path.join(rulesDir, f), "utf8").includes("AGENTS.md"))) {
    err("No .cursor/rules/*.mdc references AGENTS.md");
  }
}

if (failed) process.exit(1);
console.log("Agent drift check passed");
