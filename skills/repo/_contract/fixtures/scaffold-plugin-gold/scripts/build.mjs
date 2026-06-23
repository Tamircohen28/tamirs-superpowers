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
const DEFAULT_RULE_ORDER = ['core', 'testing', 'security', 'frontend', 'backend'];
const marker = `<!-- ${config.generatedMarker}\nSource: canonical/rules/*\nRun: npm run build\n-->\n\n`;

function loadCanonicalRules() {
  const rulesDir = path.join(root, config.canonical?.rulesDir ?? 'canonical/rules');
  const order = config.rulesOrder ?? DEFAULT_RULE_ORDER;
  const seen = new Set();
  const parts = [];

  for (const name of order) {
    const file = `${name}.md`;
    const full = path.join(rulesDir, file);
    if (fs.existsSync(full)) {
      parts.push(fs.readFileSync(full, 'utf8').trim());
      seen.add(file);
    }
  }

  if (fs.existsSync(rulesDir)) {
    for (const file of fs.readdirSync(rulesDir).filter((f) => f.endsWith('.md') && !seen.has(f)).sort()) {
      parts.push(fs.readFileSync(path.join(rulesDir, file), 'utf8').trim());
      seen.add(file);
    }
  }

  return parts.join('\n\n');
}

const allRules = loadCanonicalRules();

// dist/codex/AGENTS.md
const codexDir = path.join(root, 'dist/codex');
fs.mkdirSync(codexDir, { recursive: true });
fs.writeFileSync(
  path.join(codexDir, 'AGENTS.md'),
  `${marker}# AGENTS.md\n\nThis file is generated from \`canonical/rules/*\`.\n\n${allRules}\n`
);

// dist/cursor/.cursor/rules/000-core.mdc
const cursorRuleDir = path.join(root, 'dist/cursor/.cursor/rules');
fs.mkdirSync(cursorRuleDir, { recursive: true });
fs.writeFileSync(
  path.join(cursorRuleDir, '000-core.mdc'),
  `${marker}---\ndescription: Repository rules for all AI coding work.\nglobs:\nalwaysApply: true\n---\n\n${allRules}\n`
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
