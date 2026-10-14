# 已知陷阱与文档不一致

以下每一条都经过对本机源码的核对。**遇到与官方文档冲突时以源码为准。**

## 1. `plugins.path` 不存在

`examples/plugin/claude-web-search-router/README.md` 教用户这样配置：

```yaml
plugins:
  path:
    - /absolute/path/to/examples/plugin/bin/claude-web-search-router-go.dylib
```

但 `internal/config/config_types.go` 中 `PluginsConfig` 的字段只有 `enabled`、`dir`、`store-sources`、`store-auth`、`auth-revision`、`configs`。**没有 `path`。**

插件发现只有一条路：放进 `plugins.dir` 指向的目录（或 `<dir>/<GOOS>/<GOARCH>`），文件名即插件 ID。写 `plugins.path` 不会报错，但也不会加载任何东西。

## 2. 导入路径的 v7 / v8

`examples/plugin/README_CN.md` 的示例代码写：

```go
import "github.com/router-for-me/CLIProxyAPI/v7/sdk/pluginabi"
```

而仓库 `go.mod` 第一行是：

```
module github.com/router-for-me/CLIProxyAPI/v8
```

示例代码本身用的是 v8。**以 v8 为准。**

## 3. 文档的能力表不完整

官方《插件开发》文档的能力表没有列全宿主解析的键。以下键在 `rpc_schema.go` 中存在但文档表里没有：

- `request_lifecycle_plugin`
- `websocket_response_observer`
- `quota_provider`
- `scheduler_across_priorities`（修饰符）

以 `references/capabilities.md` 为准，它以 `rpc_schema.go` 逐条对齐。

## 4. 省略 `http_status` 会变成 500

插件执行器返回错误时如果没在错误信封里设 `http_status`，CPA 会降级为 HTTP 500，客户端会当作网关故障并退避重试。

上游返回 401 / 403 / 429 时这是错误行为。两处报错路径都要设置：

- `executor.execute`（非流式）
- `executor.execute_stream`（流式）

## 5. Windows 上无法覆盖已加载的插件

Windows 会锁住已加载的 DLL。宿主通过影子副本规避（见 `config-discovery.md`），但后果是：**替换磁盘文件不会影响正在运行的实例**。

管理接口在无法卸载时返回 `409` 并可能带 `restart_required: true`。修改插件后必须通过管理接口重新安装或重启服务，确认旧实例已卸载。

## 6. `schema_version` 为 0 表示旧版

`plugin.register` 返回的 `schema_version` 为 `0` 时，宿主按 legacy 处理。这会让流式 chunk 拦截器每次都携带完整的 `OriginalRequest` / `RequestBody` / `HistoryChunks` 副本，带来明显的每 chunk 序列化开销。

新插件应返回 `6`。

## 7. `ConfigFields` 不替代校验

`ConfigFields` 只供管理端渲染配置表单，宿主不会据此校验。插件必须在 `plugin.register` 与 `plugin.reconfigure` 中自己验证关心的字段。

同理，插件自有配置字段要保持向后兼容；删除字段时同时兼容旧配置。

## 8. 资源页不受管理鉴权保护

| 类型 | 暴露路径 | 认证 |
|---|---|---|
| 插件自有 Management API | `/v0/management/...` | 需要管理密钥 |
| 插件资源页面 | `/v0/resource/plugins/<pluginID>/...` | **不走管理鉴权** |

同源部署下，资源页的 JavaScript 可以读取管理中心 localStorage 里保存的管理密钥。

因此：

- 敏感操作必须放在 `/v0/management/...` 路由后面，由资源页读取管理密钥后调用，而不是在未鉴权的资源 GET 里直接执行。
- 资源页脚本应随插件打包，**不要加载第三方脚本**到能访问同源管理上下文的页面中。
- 安装带资源页的插件，等同于信任该插件的浏览器端代码。
- 资源路径不能包含空白、`:`、`*` 或 `..`。

## 9. 管理路由冲突会被静默跳过

插件自有 Management API 会与宿主已有 `/v0/management` 路由做冲突检查，**冲突时跳过插件路由**，不报错。注册了路由却访问不到时先查是否与宿主路由重名。

## 10. `Metadata` 与 `capabilities` 的命名风格不同

同一个注册响应里：

- `metadata` 用 Go 导出名风格：`Name`、`Version`、`GitHubRepository`、`ConfigFields`
- `capabilities` 用 snake_case：`model_provider`、`management_api`

不要为了统一而改动任何一边。

## 11. 没有 CGO 的构建不支持插件

`internal/pluginhost/support_cgo.go` 与 `support_nocgo.go` 通过构建标签切换。用 `CGO_ENABLED=0` 构建出的 CPA 二进制无法加载任何插件，且只通过响应头暴露这一事实。

## 12. 插件与宿主同进程，不可信代码不要用插件承载

标准动态库插件与 CPA 二进制同进程。宿主可以恢复部分 panic，但**不能阻止插件退出进程、破坏内存、修改进程全局状态或泄露敏感数据**。

需要隔离的代码应放在外部进程，通过 HTTP 或 CLI 集成，而不是写成插件。
