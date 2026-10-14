# cpa-plugin-dev

一个 Claude Code Agent Skill，用于开发 CLIProxyAPI（CPA）的原生插件。

CPA 的插件是加载进 CPA 进程内的原生动态库，通过稳定的 C ABI 通信。可以用 Go、C 或 Rust 编写。这个 skill 覆盖从需求解析到商店发布的完整闭环，全部内容对齐 CPA v8 源码，不依赖可能过期的文档描述。

## 安装

作为个人 skill：

```bash
cp -R cpa-plugin-dev ~/.claude/skills/
```

作为项目 skill：

```bash
mkdir -p <项目>/.claude/skills
cp -R cpa-plugin-dev <项目>/.claude/skills/
```

目录名与 frontmatter 的 `name` 必须一致，且入口是 `<name>/SKILL.md`。

## 结构

```
cpa-plugin-dev/
├── SKILL.md                    入口：触发条件、四阶段决策树、硬约束、常见误解
├── PLAN.md                     任务列表与验收标准
├── references/                 按需载入的深度材料
│   ├── phase-1-requirements.md   需求到能力的映射、配置字段设计、优先级
│   ├── phase-2-plan.md           语言选型、目录布局、构建命令
│   ├── phase-3-develop.md        cgo 骨架、dispatch、信封、各能力实现要点
│   ├── phase-4-test.md           二进制探测、开关、四个状态字段、验证矩阵
│   ├── capabilities.md           27 个能力键与对应 method（权威）
│   ├── abi-contract.md           C ABI 符号、信封、错误 http_status 映射
│   ├── host-callbacks.md         19 个 host.* 回调
│   ├── config-discovery.md       配置键、插件 ID、搜索顺序、影子副本
│   ├── packaging.md              release zip、checksums、registry.json
│   └── pitfalls.md               12 条已核对的文档与代码不一致
├── scripts/
│   ├── new-plugin.sh             从骨架生成插件目录
│   ├── build-plugin.sh           跨平台构建
│   ├── verify-plugin.sh          走管理 API v8 验证加载与生效
│   └── check-capabilities.py     校验能力声明与 dispatch 是否一致
├── assets/
│   ├── skeleton-go/              最小 Go 骨架（单个能力）
│   ├── skeleton-c/               官方 C 示例（完整能力）
│   └── skeleton-rust/            官方 Rust 示例（完整能力）
└── docs/
    ├── plugin-development.zh.md      官方《插件开发》文档正文
    └── management-api-v8.zh.md       官方《管理 API v8》文档正文
```

## 四阶段闭环

```
定制要求  →  产出计划  →  开发  →  测试
    ↑                                  |
    └──────── 反馈回阶段一 ─────────────┘
```

| 阶段 | 入口 | 关键动作 |
|---|---|---|
| 一 定制要求 | `references/phase-1-requirements.md` | 需求映射到能力，定配置字段，**不写代码** |
| 二 产出计划 | `references/phase-2-plan.md` | 选语言，跑 `new-plugin.sh`，跑通一次构建 |
| 三 开发 | `references/phase-3-develop.md` | 按骨架写，`check-capabilities.py` 自检 |
| 四 测试 | `references/phase-4-test.md` | `verify-plugin.sh`，看 `registered` 与 `effective_enabled` |

## 脚本

```bash
# 生成插件目录
scripts/new-plugin.sh my-plugin go ./out

# 构建
scripts/build-plugin.sh ./out/my-plugin go

# 自检能力声明
scripts/check-capabilities.py ./out/my-plugin

# 验证加载与生效
scripts/verify-plugin.sh my-plugin "$MANAGEMENT_KEY"
```

`check-capabilities.py` 与 `verify-plugin.sh` 需要 Python 3。`build-plugin.sh` 需要对应语言的工具链。

## 已做的验证

这个 skill 的内容不是从文档转述的，逐项对照过本机源码：

| 验证项 | 方法 | 结果 |
|---|---|---|
| 能力键清单 | 与 `internal/pluginhost/rpc_schema.go` 的 `rpcCapabilities` 逐键 diff | 27 对 27，无缺失无多余 |
| 方法名常量 | 取自 `sdk/pluginabi/types.go` | 一致 |
| 宿主回调 | 取自 `internal/pluginhost/host_callbacks.go` 的 dispatch | 19 个，一致 |
| 插件发现与扩展名 | 取自 `internal/pluginhost/platform.go` | 一致 |
| Windows 加载机制 | 取自 `internal/pluginhost/loader_windows.go` | 影子副本，已记录 |
| Go 骨架可构建 | 对本地源码 `go mod tidy` 加 `go build -buildmode=c-shared` | 成功，产出 8 MB DLL |
| 导出符号 | 在构建产物中检索四个必需符号 | 全部存在 |
| 校验脚本准确性 | 与宿主 schema diff，并对含错样例运行 | 27 对 27；含错样例报出 10 个问题 |
| **实例加载与生效** | 启动 CPA 8.0.23，装载插件，读 `GET /v8/management/plugins` | `configured`、`enabled`、`registered`、`effective_enabled` 全为 true |
| `verify-plugin.sh` 正例 | 对已加载插件运行 | 退出码 0，五个状态字段与 `path` 正确 |
| `verify-plugin.sh` 反例 | 对不存在的 id、错误管理密钥运行 | 均退出非 0，并打印已知 id 列表 |
| 管理 API 响应结构 | 与官方文档描述对照 | 文档缺 `configured` 字段，实际响应多一个 |
| 工具链兼容性 | 同一骨架用两个 MinGW 各构建一次并尝试加载 | TDM-GCC 10.3.0 失败，MinGW-W64 11.3.0 成功 |
| Rust 骨架 | `cargo build --release --locked`，再尝试加载 | 构建成功，137 KB cdylib，可加载 |
| 导出符号的真实数量 | 用 `objdump -p` 读导出表，并与宿主 `FindProc` 对照 | C 与 Rust 各 1 个，Go 4 个；宿主只按名查找 `cliproxy_plugin_init` |
| C 骨架 | 无 `cmake`，改用 `gcc -shared` 直接编译 | 构建成功，273 KB DLL，可加载，导出 1 个符号 |

最后一项是本机实测发现的真实阻塞问题，已写入 `references/pitfalls.md` 第 13 条。诊断结论是 TDM-GCC 10.3.0 链接出的 PE 节表含坏节，Windows 加载器直接拒绝整个映像。

## 布局参考

目录布局参考了 `davidvkimball/obsidian-dev-skills` 的组织方式：一个入口 `SKILL.md`
加一个按主题切分的 `references/` 目录，正文只放决策规则，细节全部下沉到参考文件。

读过该仓库 `obsidian-dev/SKILL.md` 的实际内容后，有三点观察：

**它走的是极薄路由风格。** `obsidian-dev/SKILL.md` 只有 35 行，正文仅 `Purpose`、
`Scope`、`Core Rules`、`Bundled Resources` 四节，所有实质内容都在 `references/` 下。
本 skill 的 `SKILL.md` 是 148 行，正文承载了决策树、硬约束表与常见误解表。

这个差异是**刻意保留**的。官方 skill 编写指南要求正文承载工作流与规则、控制在 500 行以内，
`skill-creator` 也把正文定位成"操作手册"而非纯索引。纯 35 行路由在 CPA 场景下会丢掉最
该前置的东西：能力选型规则、`http_status` 这类一写错就静默失败的约束。所以保留了内容，
只借用了它的**分文件方式**与**明确的资源指引段落**。

**切分维度也不同。** 那个仓库按角色拆成 dev / ops / ref / theme-dev 四个并列 skill；
本 skill 是一个 skill，`references/` 按生命周期阶段切分，因为 CPA 插件开发的难点在阶段
衔接处（能力选错要返工、声明与实现不一致会静默失败），而不是角色分工。

**表格化写法是共通的。** 正文里的 Do / Don't 表借用了同类 skill 的紧凑风格，内容全部
针对 CPA 重写，没有照抄任何一行。

## 素材来源

内容源自本机 `D:\AI\BeAnything\CPA相关` 下的材料：

- 官方《插件开发》与《管理 API v8》文档（中文页，已抽出正文存入 `docs/`）
- `CLIProxyAPI源码`，module `github.com/router-for-me/CLIProxyAPI/v8`
- `CLIProxyAPI源码/examples/plugin/` 下的 Go / C / Rust 示例

C 与 Rust 骨架是官方示例的逐字复制。Go 骨架在官方示例基础上裁剪为单个能力，原因见 `assets/README.md`。

## 已知边界

- 未覆盖 C 与 Rust 的完整实现细节，两者以官方示例作为参考实现
- `verify-plugin.sh` 的按能力验证矩阵是清单而非自动化，需要人工执行
- 商店发布流程已文档化，但未在本机走通一次真实发布
- 未包含 CPA 的嵌入 SDK（`sdk/cliproxy`），那是另一条集成路径
