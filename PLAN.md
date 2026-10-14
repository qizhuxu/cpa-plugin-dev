# CPA 插件开发 AI Skill — 任务列表

目标：产出一个符合 Agent Skills 标准、覆盖 CPA 插件开发全生命周期的可复用 skill。

素材来源（全部为本机已核对过的真实材料，禁止凭空捏造）：

| 素材 | 路径 | 用途 |
|---|---|---|
| 官方插件开发文档（中文） | `CPA相关/插件开发development.html` | 概念、能力表、宿主回调、商店格式、开发建议 |
| 官方管理 API v8 文档（中文） | `CPA相关/apiv8管理.html` | 阶段四测试验证的接口依据 |
| C ABI 契约 | `CLIProxyAPI源码/sdk/pluginabi/types.go` | 方法名常量、ABIVersion=1、SchemaVersion=6、Error.HTTPStatus |
| 宿主侧能力 schema | `CLIProxyAPI源码/sdk/pluginapi/types.go` | 全部请求/响应结构体定义 |
| 宿主真实解析的能力键 | `CLIProxyAPI源码/internal/pluginhost/rpc_schema.go` | 26 个 capability JSON 键的权威清单 |
| 加载与发现 | `CLIProxyAPI源码/internal/pluginhost/platform.go`、`loader_windows.go`、`config.go` | 搜索顺序、扩展名、Windows 影子副本 |
| 宿主回调实现 | `CLIProxyAPI源码/internal/pluginhost/host_callbacks.go` | 19 个 host.* 回调方法 |
| 多语言示例 | `CLIProxyAPI源码/examples/plugin/simple/{go,c,rust}` | 三语言最小 ABI 骨架 |
| 构建方式 | `CLIProxyAPI源码/examples/plugin/Makefile` | go buildmode=c-shared / cmake / cargo |
| 真实工程参考 | 社区 `cpa-plugin-*` 仓库结构 | cmd/ + internal/ + web/ + registry.json 布局 |

---

## 阶段 0：准备（前置依赖）

| # | 步骤 | 产出 |
|---|---|---|
| 0.1 | 建工作目录 `skills/cpa-plugin-dev/`，`git init` | 受控仓库 |
| 0.2 | 落盘任务列表 | `PLAN.md` |
| 0.3 | 把两份 HTML 正文抽成 Markdown 存进 `docs/` | `docs/plugin-development.zh.md`、`docs/management-api-v8.zh.md` |

## 阶段 1：契约层（skill 的事实基础）

| # | 步骤 | 依赖 | 产出 |
|---|---|---|---|
| 1.1 | 从 `rpc_schema.go` 提取 26 个 capability 键，配 method 名与语义 | 无 | `references/capabilities.md` |
| 1.2 | 从 `pluginabi/types.go` 提取 C ABI 符号表、信封格式、错误码与 `http_status` 映射 | 无 | `references/abi-contract.md` |
| 1.3 | 从 `host_callbacks.go` + 文档提取 19 个 `host.*` 回调签名与递归保护规则 | 无 | `references/host-callbacks.md` |
| 1.4 | 从 `config.go`/`platform.go`/`loader_windows.go` 提取配置键、搜索顺序、影子副本机制 | 无 | `references/config-discovery.md` |
| 1.5 | 汇总文档与代码不一致之处 | 1.1-1.4 | `references/pitfalls.md` |

## 阶段 2：生命周期四阶段指导

| # | 步骤 | 依赖 | 产出 |
|---|---|---|---|
| 2.1 | 阶段一 定制要求：需求→能力选型决策树、ConfigFields 设计、enabled/priority 语义 | 1.1 | `references/phase-1-requirements.md` |
| 2.2 | 阶段二 产出计划：语言选型、脚手架、构建命令、目录布局 | 1.4 | `references/phase-2-plan.md` |
| 2.3 | 阶段三 开发：ABI 骨架、信封编解码、指针与内存所有权、常见编码错误 | 1.2,1.3 | `references/phase-3-develop.md` |
| 2.4 | 阶段四 测试：本地实例启动、`/v8/management/plugins` 校验、资源页验证、热重载 | 1.4 | `references/phase-4-test.md` |
| 2.5 | 发布：release zip 命名、checksums.txt、registry.json 提交流程 | 无 | `references/packaging.md` |

## 阶段 3：可执行资产

| # | 步骤 | 依赖 | 产出 |
|---|---|---|---|
| 3.1 | 从 `examples/plugin/simple` 抽取三语言最小骨架 | 无 | `assets/skeleton-{go,c,rust}/` |
| 3.2 | 脚手架生成脚本 | 3.1 | `scripts/new-plugin.sh` |
| 3.3 | 跨平台构建脚本 | 3.1 | `scripts/build-plugin.sh` |
| 3.4 | 加载与注册验证脚本（走管理 API v8） | 2.4 | `scripts/verify-plugin.sh` |
| 3.5 | 能力声明自检脚本（校验 registration JSON 的键合法性） | 1.1 | `scripts/check-capabilities.py` |

## 阶段 4：入口与整合

| # | 步骤 | 依赖 | 产出 |
|---|---|---|---|
| 4.1 | 撰写 `SKILL.md`：前置 YAML 元数据、四阶段决策树、Do/Don't 表、reference 导航 | 全部 | `SKILL.md` |
| 4.2 | 校验 SKILL.md 合规：frontmatter 可解析、正文 <500 行、description 第三人称且含触发词 | 4.1 | 校验记录 |
| 4.3 | 撰写 `README.md` 说明安装方式与仓库结构 | 4.1 | `README.md` |

## 阶段 5：提交纪律

每个阶段完成后立即提交，commit message 使用 conventional commits：

- `chore: init cpa-plugin-dev skill workspace`
- `docs: add extracted official docs and task list`
- `feat(references): add capability and ABI contract references`
- `feat(references): add lifecycle phase guides`
- `feat(assets): add go/c/rust plugin skeletons`
- `feat(scripts): add scaffold, build and verify scripts`
- `feat: add SKILL.md entrypoint`
- `docs: add README`

## 验收标准

- [ ] `SKILL.md` frontmatter 含 `name` 与第三人称 `description`，正文不超过 500 行
- [ ] 26 个 capability 键与 `rpc_schema.go` 逐条一致
- [ ] 全部方法名与 `pluginabi/types.go` 常量一致
- [ ] 三个语言的骨架可直接构建
- [ ] 四阶段闭环均有独立 reference 且互相链接
- [ ] 无编造的接口、字段或命令
