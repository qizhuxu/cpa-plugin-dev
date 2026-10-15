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

## 13. MinGW 工具链可能产出无法加载的 DLL

这是本机实测到的问题，**在 Windows 上用 Go 写插件时最可能先撞上它**。

症状是 CPA 启动日志里出现：

```
pluginhost: failed to load plugin <id> from plugins/<id>.dll:
Failed to load .../cliproxy-pluginhost/pid-<n>/cliproxy-plugin-<id>-<hash>.dll:
%1 is not a valid Win32 application.
```

`%1 is not a valid Win32 application` 是 `ERROR_BAD_EXE_FORMAT`。它**不一定是位数不匹配**。本机两边的 PE 头都是 `machine=0x8664`（amd64），仍然报这个错。

### 真正的病因

用 `go build -buildmode=c-shared` 配 **TDM-GCC 10.3.0**（`tdm64-1`）构建出的 DLL，PE 节表是坏的：前三个节全部声明 `VirtualAddress = 0x32910000`，而 `SizeOfImage = 0x26C2000`。三个节地址相同且都落在映像之外，Windows 加载器直接拒绝整个映像。

对照数据：

| 构建方式 | 结果 |
|---|---|
| 同一 gcc 编译的纯 C DLL | 能加载 |
| TDM-GCC 10.3.0 加 Go `-buildmode=c-shared` | 加载失败，`ERROR_BAD_EXE_FORMAT` |
| MinGW-W64 11.3.0（Brecht Sanders 构建） | **能加载** |

同一个 gcc 编出的纯 C DLL 正常，说明问题出在 Go 与该 ld 的链接环节，不是工具链整体不可用。

### 排查方法

1. 先确认不是位数问题。exe 与 dll 的 PE `machine` 字段应当一致，amd64 是 `0x8664`。
2. 再查节表：每个节的 `VirtualAddress` 必须小于 `SizeOfImage`。
3. 换一个 MinGW 重编，看是否恢复：

```bash
CC="<另一个 mingw>/bin/gcc.exe" go build -buildmode=c-shared -o out.dll .
```

### 结论

**Windows 上不要默认用 `PATH` 里的第一个 `gcc`。** 构建完立刻做一次加载测试，能加载再往下走：

```bash
python -c "import ctypes; ctypes.WinDLL(r'<构建产物绝对路径>')"
```

遇到 `ERROR_BAD_EXE_FORMAT` 而位数一致时，优先怀疑工具链，换 MinGW-W64 官方构建或改用 MSVC。

## 14. 执行器插件还需要一个凭证，否则宿主根本不会调用它

实测：一个声明了 `executor` 加 `model_provider` 的插件，它的模型会出现在 `/v1/models` 里，
但真正发请求时返回：

```
HTTP 503
{"error":{"message":"auth_not_found: no auth available (providers=demo-executor, model=demo-error-model)","type":"server_error","code":"internal_server_error"}}
```

宿主在 `sdk/cliproxy/auth/conductor_execution.go` 就拒绝了，**`executor.execute` 从未被调用**。

**所以"模型注册成功"不等于"执行器能跑"。** 模型出现在列表里只证明 `model_provider` 生效了。

### 加 api-keys 组不管用

实测给该 provider 加一个 `api-keys.<provider>` 配置组（`name` 加 `base-url` 加 `keys`），
**仍然报同样的错**。这个配置组不会为插件自有 provider 产生凭证。

### 正确做法（未逐条验证）

插件自有 provider 的凭证应由插件自己的 `auth_provider` 能力提供：在 `auths/` 下放一个凭证
文件，通过 `auth.parse` 认领它并返回 `AuthData`。社区插件普遍同时声明
`auth_provider` 加 `model_provider` 加 `executor` 三个能力，就是这个原因。

**这一条只验证到"api-keys 组不行"，没有验证 auth_provider 路线确实可行。** 第一次写
执行器插件时，把"凭证从哪来"当成一个独立步骤先解决掉，再调执行逻辑。

## 15. 容器里跑 CPA，管理 API 从宿主机访问返回 403

实测：CPA 跑在容器里、端口映射到宿主机，`GET /v8/management/plugins` 返回

```
HTTP 403  {"error":"remote management disabled"}
```

容器把宿主机请求看作来自 Docker 网桥，不是 localhost，而 `management.allow-remote` 默认 `false`。**带不带管理密钥都是 403**，所以别误判成密钥错了。

在容器使用的配置里设 `management.allow-remote: true` 即可。详见 `phase-4-test.md`。

## 16. 跨发行版 glibc 版本可能导致插件加载失败

插件是原生动态库，依赖宿主环境的 glibc。官方 `Dockerfile` 运行时基底是 `debian:bookworm`（glibc 2.36），比多数开发机旧。

实测：Ubuntu 24.04（glibc 2.39）构建的插件最高只要求 `GLIBC_2.34`，在 bookworm 里能加载。但这不是必然，取决于插件用到的符号。

失败时的报错是 `version 'GLIBC_2.x' not found`，出现在 `dlopen` 阶段。

诊断与规避见 `phase-4-test.md` 的容器一节。最稳的做法是在容器基底镜像里构建。

## 17. release 里有 `_no-plugin` 变体，别下错

官方 release 每个平台提供两个包，名字只差一个后缀：

```
CLIProxyAPI_<ver>_linux_amd64.tar.gz
CLIProxyAPI_<ver>_linux_amd64_no-plugin.tar.gz
```

`no-plugin` 是 `CGO_ENABLED=0` 构建的，**加载不了任何插件**。这个区分只在响应头 `X-CPA-SUPPORT-PLUGIN` 上暴露，容易下错之后排查半天。
