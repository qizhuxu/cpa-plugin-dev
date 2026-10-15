中文 | [English](README.en.md)

# cpa-plugin-dev

一个用于开发 [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)（CPA）原生插件的 Claude Code skill。

CPA 插件是加载进 CPA 进程内的原生动态库（`.so` / `.dylib` / `.dll`），通过稳定的 C ABI 通信，可以用 Go、C 或 Rust 编写。这个 skill 覆盖从需求到商店发布的完整闭环，全部内容对齐 CPA v8 源码，而不是转述可能已经过期的文档。

## 安装

### Claude Code 插件

在会话里：

```
/plugin marketplace add qizhuxu/cpa-plugin-dev
/plugin install cpa-plugin-dev@cpa-plugin-dev
```

在终端里，非交互：

```bash
claude plugin marketplace add qizhuxu/cpa-plugin-dev
claude plugin install cpa-plugin-dev@cpa-plugin-dev --scope user -y
```

### npx

```bash
npx cpa-plugin-dev --global    # 装到 ~/.claude/skills
npx cpa-plugin-dev             # 装到 ./.claude/skills
```

常用参数：`--dir <path>` 指定目标目录，`--agent codex`（或 `agents`、`cursor`、`opencode`）装到别的 agent 的 skills 目录，另外还有 `--list`、`--dry-run`、`--force`、`--help`。

用开放的 skills CLI：

```bash
npx skills add qizhuxu/cpa-plugin-dev
```

或者直接从 git 地址走，完全不经过 npm：

```bash
npx github:qizhuxu/cpa-plugin-dev --global
```

### 手动

```bash
git clone https://github.com/qizhuxu/cpa-plugin-dev
cp -R cpa-plugin-dev/skills/cpa-plugin-dev ~/.claude/skills/
```

目录名必须与 frontmatter 里的 `name` 一致，入口必须是 `<name>/SKILL.md`。

## 覆盖内容

| 阶段 | 参考文件 | 产出 |
|---|---|---|
| 一 定制要求 | `references/phase-1-requirements.md` | 需求映射到能力，设计配置字段 |
| 二 产出计划 | `references/phase-2-plan.md` | 选语言，脚手架，跑通一次构建 |
| 三 开发 | `references/phase-3-develop.md` | cgo 骨架、dispatch、信封、各能力要点 |
| 四 测试 | `references/phase-4-test.md` | 二进制探测、开关、状态字段、验证矩阵 |

契约层，按需载入：

- `references/capabilities.md` — 全部 27 个能力键与对应方法
- `references/abi-contract.md` — 导出符号、JSON 信封、`http_status` 映射
- `references/host-callbacks.md` — 19 个 `host.*` 回调
- `references/config-discovery.md` — 配置键、插件 ID、搜索顺序、影子副本
- `references/packaging.md` — release zip、`checksums.txt`、`registry.json`
- `references/pitfalls.md` — 17 条已核对的文档与代码不一致

## 脚本

```bash
skills/cpa-plugin-dev/scripts/new-plugin.sh my-plugin go ./out
skills/cpa-plugin-dev/scripts/build-plugin.sh ./out/my-plugin go
skills/cpa-plugin-dev/scripts/check-capabilities.py ./out/my-plugin
skills/cpa-plugin-dev/scripts/verify-plugin.sh my-plugin "$MANAGEMENT_KEY"
```

`check-capabilities.py`、`plan-capabilities.py` 与 `verify-plugin.sh` 需要 Python 3。`build-plugin.sh` 需要所选语言的工具链。

## 验证情况

内容不是从文档转述的，逐项对照过 CPA v8 源码与一个真实实例：

- 能力键清单与 `internal/pluginhost/rpc_schema.go` 逐键 diff — 27 对 27
- 宿主回调取自 `internal/pluginhost/host_callbacks.go` — 19 个，一致
- Windows 加载取自 `loader_windows.go`（影子副本），Linux 取自 `loader_unix.go`（`dlopen` 配 `RTLD_NOW | RTLD_LOCAL`）
- Go、C、Rust 三语言骨架在 Windows 与 Linux 上都实测构建并加载
- 在 Linux CPA v8.0.28 与 `eceasy/cli-proxy-api` Docker 镜像里端到端跑通
- 跨发行版 glibc 实测：Ubuntu 24.04 的构建产物能在 `debian:bookworm` 里加载

Linux 与 Docker 的结果来自一台独立的 Ubuntu 24.04 机器，不是在本机推断的。那一轮实测额外暴露了本 skill 的四个缺陷，均已修复。

## 仓库结构

```
cpa-plugin-dev/
├── .claude-plugin/          插件与商店清单
├── cli/install.mjs          npx 安装器
├── skills/cpa-plugin-dev/   skill 本体
├── package.json
└── LICENSE
```

## 已知边界

- C 与 Rust 只覆盖到官方示例的程度，不是穷尽式
- `phase-4-test.md` 里的按能力验证矩阵是清单，不是自动化测试
- 商店发布流程已文档化，但没有走过一次真实发布
- 嵌入 SDK（`sdk/cliproxy`）是另一条集成路径，不在范围内

## 许可

MIT
