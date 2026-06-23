#!/usr/bin/env node
/**
 * build.mjs — stub adapter generator for agent-kit repos.
 * Reads canonical/ and writes dist/ + plugins/<name>/skills/.
 * Replace with full Handlebars pipeline in a follow-up.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const config = JSON.parse(fs.readFileSync(path.join(root, 'agent-kit.config.json'), 'utf8'));
const marker = `<!-- ${config.generatedMarker}\nSource: canonical/rules/core.md\nRun: npm run build\n-->\n\n`;

const core = fs.readFileSync(path.join(root, 'canonical/rules/core.md'), 'utf8');

// dist/codex/AGENTS.md
const codexDir = path.join(root, 'dist/codex');
fs.mkdirSync(codexDir, { recursive: true });
fs.writeFileSync(
  path.join(codexDir, 'AGENTS.md'),
  `${marker}# AGENTS.md\n\nThis file is generated from \`canonical/rules/*\`.\n\n${core}\n`
);

// dist/cursor/.cursor/rules/000-core.mdc
const cursorRuleDir = path.join(root, 'dist/cursor/.cursor/rules');
fs.mkdirSync(cursorRuleDir, { recursive: true });
fs.writeFileSync(
  path.join(cursorRuleDir, '000-core.mdc'),
  `${marker}---\ndescription: Core repository rules for all AI coding work.\nglobs:\nalwaysApply: true\n---\n\n# Core Rules\n\n${core}\n`
);

// Copy canonical skills into plugin wrapper
const pluginSkills = path.join(root, config.dist.claudePlugin, 'skills');
fs.mkdirSync(pluginSkills, { recursive: true });
const canonicalSkills = path.join(root, 'canonical/skills');
for (const entry of fs.readdirSync(canonicalSkills, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const src = path.join(canonicalSkills, entry.name);
  const dest = path.join(pluginSkills, entry.name);
  fs.cpSync(src, dest, { recursive: true, force: true });
}

console.log('build.mjs stub complete — dist/ and plugin skills updated');
