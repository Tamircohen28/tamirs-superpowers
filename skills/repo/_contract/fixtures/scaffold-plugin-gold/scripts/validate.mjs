#!/usr/bin/env node
/**
 * validate.mjs — layout and GENERATED marker checks for agent-kit repos.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

const required = [
  'canonical/rules/core.md',
  'agent-kit.config.json',
  'scripts/build.mjs',
  '.claude-plugin/marketplace.json',
  'dist/codex/AGENTS.md',
  'dist/cursor/.cursor/rules/000-core.mdc',
];

let failed = 0;
for (const rel of required) {
  const p = path.join(root, rel);
  if (!fs.existsSync(p)) {
    console.error(`MISSING: ${rel}`);
    failed++;
  }
}

for (const rel of ['dist/codex/AGENTS.md', 'dist/cursor/.cursor/rules/000-core.mdc']) {
  const text = fs.readFileSync(path.join(root, rel), 'utf8');
  if (!text.includes('GENERATED FILE')) {
    console.error(`NO GENERATED MARKER: ${rel}`);
    failed++;
  }
}

const pluginsDir = path.join(root, 'plugins');
if (fs.existsSync(pluginsDir)) {
  const wrappers = fs.readdirSync(pluginsDir, { withFileTypes: true }).filter((d) => d.isDirectory());
  if (wrappers.length === 0) {
    console.error('MISSING: plugins/<name>/ wrapper');
    failed++;
  } else {
    const manifest = path.join(pluginsDir, wrappers[0].name, '.claude-plugin/plugin.json');
    if (!fs.existsSync(manifest)) {
      console.error('MISSING: plugins/<name>/.claude-plugin/plugin.json');
      failed++;
    }
  }
}

if (failed > 0) {
  console.error(`validate.mjs failed (${failed} issue(s))`);
  process.exit(1);
}
console.log('validate.mjs passed');
