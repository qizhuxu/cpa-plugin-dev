#!/usr/bin/env node
// Installer for the cpa-plugin-dev agent skill.
//
// Copies skills/cpa-plugin-dev/ from this package into an agent skills
// directory. Default target is the project-level Claude Code directory; use
// --global for the user-level one, or --dir to point somewhere else.

import { cp, mkdir, readdir, rm, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(HERE, "..");
const SKILLS_SRC = path.join(PKG_ROOT, "skills");

// agent flag -> directory that agent reads skills from, relative to a base dir
const AGENT_DIRS = {
  claude: ".claude/skills",
  "claude-code": ".claude/skills",
  agents: ".agents/skills",
  codex: ".codex/skills",
  cursor: ".cursor/skills",
  opencode: ".opencode/skills",
};

function usage() {
  const lines = [
    "cpa-plugin-dev - install the CLIProxyAPI plugin development skill",
    "",
    "Usage:",
    "  npx cpa-plugin-dev                 install into ./.claude/skills",
    "  npx cpa-plugin-dev --global        install into ~/.claude/skills",
    "  npx cpa-plugin-dev --dir <path>    install into <path>/<skill-name>",
    "  npx cpa-plugin-dev --agent <name>  choose the agent directory",
    "  npx cpa-plugin-dev --list          show the skills in this package",
    "",
    "Options:",
    "  -g, --global         use the user home directory instead of the cwd",
    "  -d, --dir <path>     install under this directory instead of an agent dir",
    "  -a, --agent <name>   " + Object.keys(AGENT_DIRS).join(", "),
    "  -f, --force          overwrite an existing installation",
    "  -n, --dry-run        print what would happen, copy nothing",
    "  -l, --list           list bundled skills and exit",
    "  -h, --help           show this message",
    "",
    "Other ways to install:",
    "  Claude Code plugin   /plugin marketplace add <owner>/cpa-plugin-dev",
    "  skills CLI           npx skills add <owner>/cpa-plugin-dev",
    "  manual               copy skills/cpa-plugin-dev into ~/.claude/skills/",
  ];
  console.log(lines.join("\n"));
}

function fail(message) {
  console.error("error: " + message);
  process.exit(1);
}

function parseArgs(argv) {
  const opts = {
    global: false,
    dir: null,
    agent: "claude",
    force: false,
    dryRun: false,
    list: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "-g" || a === "--global") opts.global = true;
    else if (a === "-f" || a === "--force") opts.force = true;
    else if (a === "-n" || a === "--dry-run") opts.dryRun = true;
    else if (a === "-l" || a === "--list") opts.list = true;
    else if (a === "-h" || a === "--help") opts.help = true;
    else if (a === "-d" || a === "--dir") {
      if (i + 1 >= argv.length) fail("--dir needs a path");
      opts.dir = argv[++i];
    } else if (a === "-a" || a === "--agent") {
      if (i + 1 >= argv.length) fail("--agent needs a name");
      opts.agent = argv[++i];
    } else if (a.startsWith("--dir=")) opts.dir = a.slice("--dir=".length);
    else if (a.startsWith("--agent=")) opts.agent = a.slice("--agent=".length);
    else fail("unknown option: " + a + " (try --help)");
  }
  return opts;
}

// A bundled skill is any immediate child of skills/ that holds a SKILL.md.
async function listBundledSkills() {
  if (!existsSync(SKILLS_SRC)) fail("skills/ is missing from this package");
  const entries = await readdir(SKILLS_SRC, { withFileTypes: true });
  const found = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    if (existsSync(path.join(SKILLS_SRC, entry.name, "SKILL.md"))) {
      found.push(entry.name);
    }
  }
  return found.sort();
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.help) {
    usage();
    return;
  }

  const skills = await listBundledSkills();

  if (opts.list) {
    console.log("skills in this package:");
    for (const name of skills) console.log("  " + name);
    return;
  }

  if (skills.length === 0) fail("no skills found in skills/");
  if (!opts.dir && !(opts.agent in AGENT_DIRS)) {
    const known = Object.keys(AGENT_DIRS).join(", ");
    fail("unknown agent: " + opts.agent + " (known: " + known + ")");
  }

  const base = opts.dir
    ? path.resolve(opts.dir)
    : path.resolve(opts.global ? homedir() : process.cwd(), AGENT_DIRS[opts.agent]);

  let installed = 0;
  let skipped = 0;

  for (const name of skills) {
    const from = path.join(SKILLS_SRC, name);
    const to = path.join(base, name);
    const alreadyThere = existsSync(to);

    if (alreadyThere && !opts.force) {
      console.log("skip    " + to);
      console.log("        already installed; pass --force to overwrite");
      skipped++;
      continue;
    }

    if (opts.dryRun) {
      console.log((alreadyThere ? "replace " : "install ") + to);
      installed++;
      continue;
    }

    await mkdir(base, { recursive: true });
    if (alreadyThere) await rm(to, { recursive: true, force: true });
    await cp(from, to, { recursive: true });
    console.log("install " + to);
    installed++;
  }

  console.log("");

  if (opts.dryRun) {
    console.log("dry run: nothing was written");
    return;
  }

  console.log(installed + " installed, " + skipped + " skipped");

  for (const name of skills) {
    const to = path.join(base, name);
    if (!existsSync(to)) continue;
    const entries = await readdir(to, { withFileTypes: true });
    console.log("  " + name + ": SKILL.md plus " + entries.length + " entries");
  }

  console.log("");
  console.log("Claude Code picks the skill up on its next start. Check with /skills.");
}

main().catch((err) => {
  console.error("error: " + err.message);
  process.exit(1);
});
