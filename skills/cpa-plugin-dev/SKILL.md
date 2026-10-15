---
name: cpa-plugin-dev
description: Build, review, debug, scaffold, and package native plugins for CLIProxyAPI (CPA). Use when working on a CPA plugin in Go, C, or Rust; when declaring plugin capabilities such as executor, auth_provider, model_router, scheduler, request or response translators, interceptors, management_api, or quota_provider; when implementing the cliproxy_plugin_init C ABI, the JSON RPC envelope, or host callbacks; when debugging why a plugin reports registered false or effective_enabled false; or when packaging a release zip, checksums.txt, or a registry.json entry. Also use when the user mentions cpa-plugin, CLIProxyAPI-Plugins-Store, cliproxy_plugin_init, or plugins.configs.
license: MIT
metadata:
  version: 1.0.0
  source: derived from CLIProxyAPI v8 source and official plugin documentation
---

# CPA 插件开发

CLIProxyAPI 的插件是**原生动态库**，加载进 CPA 进程内，通过稳定的 C ABI 通信。宿主调用插件用 method 名加字节数组，插件反向调用宿主用同一套机制。

这个 skill 覆盖从需求到上线的四阶段闭环，全部内容对齐本机 CPA 源码，不依赖文档中可能过期的描述。

## 什么时候用

- 要写一个新的 CPA 插件，或者要给已有插件加能力
- 插件加载了但不生效（`registered: false` 或 `effective_enabled: false`）
- 请求返回了错误的 HTTP 状态码（尤其是全都变成 500）
- 要把插件发布到商店
- 要评审一个 CPA 插件的实现

**不适用**：给 Claude Code 本身写插件（那是另一套机制）；使用 CPA 做代理转发而不是开发插件。

## 先读哪一份

不要通读全部参考文件。按当前阶段读一份，需要时再读相邻的。

| 你现在要做的事 | 读这个 |
|---|---|
| 搞清需求该对应哪个能力 | `references/phase-1-requirements.md` |
| 把选好的能力变成声明与配置草案 | `scripts/plan-capabilities.py` |
| 定语言、建目录、跑通构建 | `references/phase-2-plan.md` |
| 写代码、调 ABI、处理错误 | `references/phase-3-develop.md` |
| 验证插件真的生效了 | `references/phase-4-test.md` |
| 发布到商店 | `references/packaging.md` |
| 查某个能力的确切 JSON 键与 method | `references/capabilities.md` |
| 查 C ABI 符号、信封、错误码映射 | `references/abi-contract.md` |
| 查宿主回调怎么调 | `references/host-callbacks.md` |
| 查配置键、插件发现顺序 | `references/config-discovery.md` |
| 遇到反直觉的行为 | `references/pitfalls.md` |
| 看官方文档原文 | `docs/plugin-development.zh.md`、`docs/management-api-v8.zh.md` |

## 四阶段闭环

```
定制要求  →  产出计划  →  开发  →  测试
    ↑                                  |
    └──────── 反馈回阶段一 ─────────────┘
```

### 阶段一：定制要求

**不要先写代码。** 先把"我想让 CPA 做 X"映射成能力清单。

三条判断规则：

1. **能选加工能力就别选入口能力。** translator、normalizer、interceptor 只改数据；executor、scheduler、model_router 参与路由决策，出错影响面大得多。
2. **只有要发往 CPA 不认识的上游时才需要 `executor`。** 改造已有上游的请求或响应，用 translator 或 normalizer。
3. **声明了就一定要实现。** 宿主按声明调用，声明了却返回 `unknown_method` 会污染该阶段的所有请求。

产出：能力清单、配置字段草案、优先级理由、**不做清单**。

选好能力后直接跑一次，把结论落成可粘贴的文本：

```bash
scripts/plan-capabilities.py <能力键>... --id <plugin-id>
```

它会输出 `capabilities` 对象、dispatch 必须覆盖的方法清单、`plugins.configs` 配置块，
并在你选了修饰键却没选对应基础能力时给出提示。

### 阶段二：产出计划

```bash
scripts/new-plugin.sh <plugin-id> [go|c|rust] [输出目录]
```

默认 Go。JSON 与 base64 由标准库处理，SDK 结构体可直接 import。选 C 或 Rust 的唯一理由是要复用的既有代码是那个语言。

产出：可构建的骨架、能跑通一次构建、方案文档。

### 阶段三：开发

按 `references/phase-3-develop.md` 的骨架写。核心是四件事：

1. `cliproxy_plugin_init` 回填函数表并保存宿主函数表
2. `handleMethod` 的 `switch` 覆盖声明的全部 method，`default` 返回 `unknown_method`
3. 错误路径**必须**设 `http_status`
4. 响应缓冲区用 `C.CBytes` 分配

写完先跑自检：

```bash
scripts/check-capabilities.py <插件目录>
```

它会抓出拼错的能力键、声明了但没实现的方法、以及声明 `executor` 却没给格式。

### 阶段四：测试

```bash
scripts/verify-plugin.sh <plugin-id> [管理密钥] [base-url]
```

**只有 `registered` 与 `effective_enabled` 同时为真才算生效。** 只看 `enabled` 会把"配置开了但库没加载"误判成成功。

改完代码必须走卸载接口或重启：Windows 会锁住已加载的 DLL，宿主从影子副本加载，替换磁盘文件不影响运行中的实例。

## 硬约束

这些是源码层面确定的，违反了会直接出错：

| 约束 | 后果 |
|---|---|
| 错误信封不设 `http_status` | 一律降级为 HTTP 500，客户端退避重试 |
| 用 Go 内存写 `response.ptr` | 宿主用 C `free` 释放时崩溃 |
| 返回 Go `error` 对象 | 无法跨越 C ABI，宿主收到空响应 |
| 嵌套调 `host.model.*` 不转发 `host_callback_id` | 插件递归调用自己 |
| 声明了能力但 dispatch 没覆盖其 method | 宿主收到 `unknown_method` |
| `schema_version` 返回 0 | 每个流式 chunk 都带完整请求体副本 |
| 插件里调 `os.Exit` / `log.Fatal` | 宿主进程一起退出 |
| 流式资源不调 `*_stream_close` | 流资源泄漏 |

## 常见误解

| 误解 | 事实 |
|---|---|
| 可以用 `plugins.path` 指向动态库 | **没有这个键。** 只有 `plugins.dir` 加文件名 |
| 只开单插件 `enabled` 就行 | 全局 `plugins.enabled` 与单插件 `enabled` 是两个独立开关 |
| 导入路径是 `v7` | 仓库 module 是 `v8`，示例 README 里的 v7 是过期内容 |
| 改了 `.dll` 就生效 | 运行中的实例不受影响，必须重新加载或重启 |
| 资源页需要管理密钥 | `/v0/resource/plugins/...` **不走管理鉴权**，敏感操作要放 `/v0/management/...` |
| 文档的能力表是全的 | 文档缺 `request_lifecycle_plugin`、`websocket_response_observer`、`quota_provider` 等，以 `references/capabilities.md` 为准 |
| 插件可以承载不可信代码 | 插件与宿主同进程，可以退出进程、破坏内存、泄露数据 |

## 做与不做

| 做 | 不做 |
|---|---|
| 插件自己的 HTTP 请求走 `host.http.*` | 自己发 HTTP，绕过宿主代理与日志 |
| 需要模型请求时走 `host.model.*` | 把宿主凭证复制进插件 |
| 一次只加一个能力，加完就验证 | 一次声明一堆能力 |
| 注册时只返回元数据与能力声明 | 在 `plugin.register` 里做重活，阻塞宿主启动 |
| 日志只记结构 | 日志里输出密钥、token、原始凭证 JSON |
| 插件自有配置字段保持向后兼容 | 删字段时不管旧配置 |

## 关键事实速查

- ABI 版本 `1`，RPC schema 版本 `6`
- 能力 JSON 键共 **27** 个：24 个布尔开关加 3 个执行器修饰字段
- 插件 ID 来自动态库**文件名去扩展名**，需匹配 `[A-Za-z0-9][A-Za-z0-9._-]{0,127}`
- 搜索顺序：`plugins/<GOOS>/<GOARCH>` 优先于 `plugins` 根目录
- 扩展名：Linux `.so`，macOS `.dylib`，Windows `.dll`
- 宿主回调共 19 个，前缀 `host.`
- 插件发现只认目录，不认路径配置
- 没有 CGO 的 CPA 二进制无法加载插件，只通过响应头 `httpX-CPA-SUPPORT-PLUGIN` 暴露这一事实
