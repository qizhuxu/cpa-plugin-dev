[中文](README.md) | English

# cpa-plugin-dev

A Claude Code skill for building native plugins for [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (CPA).

CPA plugins are native shared libraries (`.so` / `.dylib` / `.dll`) loaded into the CPA process and spoken to over a stable C ABI. They can be written in Go, C or Rust. This skill covers the full loop from requirement to store release, and every fact in it is checked against the CPA v8 source rather than against documentation that may have drifted.

## Install

### Claude Code plugin

In a session:

```
/plugin marketplace add qizhuxu/cpa-plugin-dev
/plugin install cpa-plugin-dev@cpa-plugin-dev
```

From a shell, non-interactive:

```bash
claude plugin marketplace add qizhuxu/cpa-plugin-dev
claude plugin install cpa-plugin-dev@cpa-plugin-dev --scope user -y
```

### npx

```bash
npx cpa-plugin-dev --global    # installs into ~/.claude/skills
npx cpa-plugin-dev             # installs into ./.claude/skills
```

Useful flags: `--dir <path>` for a target directory, `--agent codex` (or `agents`, `cursor`, `opencode`) for another agent's skills directory, plus `--list`, `--dry-run`, `--force` and `--help`.

With the open skills CLI:

```bash
npx skills add qizhuxu/cpa-plugin-dev
```

Or straight from the git URL, with no npm package involved:

```bash
npx github:qizhuxu/cpa-plugin-dev --global
```

### Manual

```bash
git clone https://github.com/qizhuxu/cpa-plugin-dev
cp -R cpa-plugin-dev/skills/cpa-plugin-dev ~/.claude/skills/
```

The directory name must match the `name` field in the frontmatter, and the entry point must be `<name>/SKILL.md`.

## What it covers

| Stage | Reference | What you get |
|---|---|---|
| 1 Requirements | `references/phase-1-requirements.md` | map a requirement onto capabilities, design the config fields |
| 2 Plan | `references/phase-2-plan.md` | pick a language, scaffold, get one build passing |
| 3 Develop | `references/phase-3-develop.md` | cgo skeleton, dispatch, envelope, per-capability notes |
| 4 Test | `references/phase-4-test.md` | binary probe, toggles, the status fields, verification matrix |

Contract layer, loaded only when needed:

- `references/capabilities.md` — all 27 capability keys and the methods each one implies
- `references/abi-contract.md` — the exported symbol, the JSON envelope, the `http_status` mapping
- `references/host-callbacks.md` — the 19 `host.*` callbacks
- `references/config-discovery.md` — config keys, plugin IDs, search order, Windows shadow copies
- `references/packaging.md` — release zip, `checksums.txt`, `registry.json`
- `references/pitfalls.md` — 17 checked documentation-versus-code discrepancies

## Scripts

```bash
skills/cpa-plugin-dev/scripts/new-plugin.sh my-plugin go ./out
skills/cpa-plugin-dev/scripts/build-plugin.sh ./out/my-plugin go
skills/cpa-plugin-dev/scripts/check-capabilities.py ./out/my-plugin
skills/cpa-plugin-dev/scripts/verify-plugin.sh my-plugin "$MANAGEMENT_KEY"
```

`check-capabilities.py`, `plan-capabilities.py` and `verify-plugin.sh` need Python 3. `build-plugin.sh` needs the toolchain for the language you picked.

## Verified against

The content is not transcribed from documentation. It was checked against the CPA v8 source and a live instance:

- the capability key list diffed against `internal/pluginhost/rpc_schema.go` — 27 of 27
- host callbacks from `internal/pluginhost/host_callbacks.go` — 19, matching
- Windows loading from `loader_windows.go` (shadow copies), Linux from `loader_unix.go` (`dlopen` with `RTLD_NOW | RTLD_LOCAL`)
- the Go, C and Rust skeletons built and loaded on Windows and on Linux
- end to end on Linux CPA v8.0.28 and inside the `eceasy/cli-proxy-api` Docker image
- cross-distribution glibc checked: an Ubuntu 24.04 build loads on `debian:bookworm`

The Linux and Docker results come from a separate Ubuntu 24.04 machine, not from inference. That run exposed four defects in this skill, all of which have since been fixed.

## Layout

```
cpa-plugin-dev/
├── .claude-plugin/          plugin and marketplace manifests
├── cli/install.mjs          the npx installer
├── skills/cpa-plugin-dev/   the skill itself
├── package.json
└── LICENSE
```

## Known limits

- C and Rust are covered at the level of the official examples, not exhaustively
- the per-capability verification matrix in `phase-4-test.md` is a checklist, not an automated test
- store publishing is documented but has not been exercised as a real release
- the embedded SDK (`sdk/cliproxy`) is a separate integration path and is out of scope

## License

MIT
