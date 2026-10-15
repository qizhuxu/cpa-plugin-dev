# 配置与插件发现

来源：`internal/config/config_types.go`、`internal/pluginhost/config.go`、`internal/pluginhost/platform.go`、`internal/pluginhost/loader_windows.go`、`config.example.yaml`。

## 全局配置节

`PluginsConfig` 的**全部**字段：

| YAML 键 | 类型 | 说明 |
|---|---|---|
| `enabled` | bool | 全局插件加载开关，默认 `false` |
| `dir` | string | 插件发现目录，默认 `"plugins"` |
| `store-sources` | string 数组 | 追加的第三方插件商店 registry URL |
| `store-auth` | 对象数组 | 商店请求的认证规则，密钥从环境变量读取 |
| `auth-revision` | int | Home 管理的插件凭证版本号，不要手工编辑 |
| `configs` | map | 按插件 ID 索引的实例配置 |

最小可用配置：

```yaml
plugins:
  enabled: true
  dir: "plugins"
  configs:
    example-provider:
      enabled: true
      priority: 1
      mode: "safe"      # 插件自有字段，宿主原样保留
```

**没有 `plugins.path` 键。** 见 `pitfalls.md`。

## 单插件配置

| 键 | 说明 |
|---|---|
| `enabled` | 单个插件开关。未写时按 `false` 处理 |
| `priority` | 启动、注册与路由顺序。**高优先级先处理** |
| 其他字段 | 插件自有配置，宿主原样保留并通过 `config_yaml` 传给插件 |

宿主只解析 `enabled` 与 `priority`，其余字段作为一个 YAML 子树原样透传。管理 API 更新配置时会尽量保留原有 YAML 树，只改请求指定的字段。

## 插件 ID

插件 ID 来自动态库**文件名去掉扩展名**：

```
plugins/darwin/arm64/example-provider.dylib   ->   example-provider
```

必须匹配 `[A-Za-z0-9][A-Za-z0-9._-]{0,127}`。

`plugin.register` 返回的 `metadata.Name` 与文件名的关系要留意：配置键、`plugins.configs.<id>` 与资源路径 `/v0/resource/plugins/<id>/` 用的是**文件名的 ID**。

## 目录搜索顺序

宿主按当前平台依次搜索，**靠前的目录先生效**：

```
plugins/<GOOS>/<GOARCH>-<variant>
plugins/<GOOS>/<GOARCH>
plugins
```

`internal/pluginhost/platform.go` 中实际构造的候选目录是 `filepath.Join(root, goos, goarch)` 与 `root` 两级。扩展名按平台决定：

| 平台 | 扩展名 |
|---|---|
| macOS | `.dylib` |
| Linux / FreeBSD | `.so` |
| Windows | `.dll` |

同一个插件 ID 在多个目录出现时，优先级更高的目录先生效。

## Windows 专属：影子副本加载

`loader_windows.go` 使用 `syscall.LoadDLL`，并且**不直接从原路径加载**，而是先做一次 shadow copy：

```
shadowCopyPlugin(file) -> 复制到进程私有的影子目录 -> 从影子路径 LoadDLL
```

原因：Windows 会锁住已加载的 DLL 文件，无法原地覆盖。影子副本让宿主能在插件运行期间替换磁盘上的原文件，并在下次加载时生效。

影子目录按进程 ID 命名（`shadowPluginProcessDirName(pid)`），启动时会清理陈旧的影子文件（`removeStaleShadowPlugins`），并按内容摘要校验是否可复用（`shadowPluginMatches`）。

这解释了为什么**修改插件后必须触发重新加载或重启**：仅替换磁盘文件不会让已加载的实例改变。

**影子副本是 Windows 专属机制。** Linux 与 macOS 走 `loader_unix.go`，直接 `dlopen(file.Path)`，没有影子副本。

## Linux / macOS 加载机制

`internal/pluginhost/loader_unix.go` 用 `dlopen(path, RTLD_NOW | RTLD_LOCAL)`，然后 `dlsym(handle, "cliproxy_plugin_init")`。

两个 flag 的含义值得记住：

| flag | 含义 |
|---|---|
| `RTLD_NOW` | 加载时解析全部未定义符号。缺依赖库会在加载阶段立刻失败，而不是等到调用时 |
| `RTLD_LOCAL` | 插件符号不进入全局命名空间。插件之间不会符号冲突，但也别指望靠符号插入互相影响 |

**Linux 上的加载失败信息与 Windows 完全不同**，宿主报的是 `dlopen <路径>: <dlerror()>`。常见 dlerror 文本：

| dlerror 文本 | 含义 | Windows 对应 |
|---|---|---|
| `invalid ELF header` | 架构不符或文件不是 ELF | `%1 is not a valid Win32 application` |
| `wrong ELF class: ELFCLASS32` | 32 位库装进 64 位宿主 | 同上 |
| `cannot open shared object file` | 文件不存在，或依赖库缺失 | `The specified module could not be found` |
| `undefined symbol: X` | 某个符号没解析到（`RTLD_NOW` 直接拒绝） | 通常是加载期无提示，调用时崩 |
| `file too short` | 文件被截断，构建没写完 | 同类 |

排查顺序与 Windows 一致：先看文件名与扩展名，再看架构，最后看依赖。

## 配置热重载

`config.yaml` 变更由 `internal/watcher/` 热重载。插件配置变更会触发 `plugin.reconfigure`。全局 `plugins.enabled` 从 `false` 变 `true` 需要重新扫描目录。

## 管理接口

v0 与 v8 两套路径都可用，v8 是新契约。

| 方法与路径 | 作用 |
|---|---|
| `GET /v8/management/plugins` | 列出已发现、已配置、已注册插件，返回 `plugins_enabled`、`plugins_dir`、每个插件的 `id`、`path`、启用状态、元数据、配置字段与菜单 |
| `DELETE /v8/management/plugins/:id` | 删除本地动态库及保存的配置；无法卸载时返回 `409` 并可能带 `restart_required: true` |
| `GET /v8/management/plugins/store` | 商店目录、源错误、安装状态与可用更新 |
| `POST /v8/management/plugins/store/:id/install` | 下载或更新插件并启用；ID 冲突时用 `?source=<source-id>` |
| `GET /v8/management/plugins/:id/quota?auth_index=` | 查询插件配额提供方 |
| `PUT/PATCH /v8/management/config/plugins/configs/<id>` | 替换或合并该插件配置对象 |
| `PUT /v8/management/config/plugins/configs/<id>/enabled` | 只改该开关，**不改** `plugins.enabled` |

### `GET /v8/management/plugins` 的实际响应结构

实测响应（CPA 8.0.23）：

```json
{
  "plugins_enabled": true,
  "plugins_dir": "plugins",
  "plugins": [
    {
      "id": "demo-normalizer",
      "path": "plugins/demo-normalizer.dll",
      "configured": true,
      "enabled": true,
      "registered": true,
      "effective_enabled": true,
      "supports_oauth": false,
      "oauth_provider": "",
      "supports_quota": false,
      "logo": "",
      "config_fields": [
        { "name": "mode", "type": "enum", "enum_values": ["safe", "fast"], "description": "..." }
      ],
      "menus": [],
      "metadata": {
        "name": "demo-normalizer",
        "version": "0.1.0",
        "author": "...",
        "github_repository": "https://github.com/owner/demo-normalizer",
        "logo": "",
        "config_fields": []
      }
    }
  ]
}
```

`metadata` 里是 **snake_case**（`github_repository`、`config_fields`），而注册响应里插件**返回**的是 Go 导出名风格（`GitHubRepository`、`ConfigFields`）。宿主在转成管理 API 响应时做了改名。

### 五个状态字段

| 字段 | 含义 |
|---|---|
| `plugins_enabled` | 全局开关，位于响应顶层 |
| `configured` | 该插件有 `plugins.configs.<id>` 条目 |
| `enabled` | 单插件配置开关 |
| `registered` | 动态库已加载并完成注册 |
| `effective_enabled` | 以上条件同时满足后的实际启用状态 |

**验证插件是否真正生效，看 `registered` 与 `effective_enabled`，不要只看 `enabled`。**

官方《插件开发》文档只列了四个字段，`configured` 是实际响应里多出来的第五个。插件没写进 `plugins.configs` 时 `configured` 为 `false`，此时即使动态库能加载也不会注册。

`path` 是**相对于 CPA 工作目录**的路径。加载失败时日志里出现的是影子副本的绝对路径，两者不同，不要混淆。

`menus` 是插件通过 `management.register` 返回的 `resources` 数组，条目形如 `{path, menu, description}`。

**路径在注册与查询两个方向上的形式不同，容易搞错：**

| 方向 | 形式 | 例子 |
|---|---|---|
| 插件注册时返回 | **相对路径** | `"/status"` |
| 管理 API 查询时返回 | **绝对路径** | `"/v0/resource/plugins/demo-management/status"` |

宿主在注册时把相对路径拼到 `/v0/resource/plugins/<pluginID>/` 下，查询时回显拼好的完整路径。写校验脚本时不要再拼一次前缀，否则会得到重复路径。

实测的鉴权边界：

| 路径 | 不带管理密钥 |
|---|---|
| `/v0/resource/plugins/demo-management/status` | `200`，正常返回页面 |
| `/v0/management/plugins/demo-management/status` | `401` |

这印证了 `pitfalls.md` 第 8 条：资源页不走管理鉴权，敏感操作必须放在 `/v0/management/...` 路由后面。

## 构建能力探测

管理 API 响应带 `httpX-CPA-SUPPORT-PLUGIN` 头：`1` 表示当前二进制支持动态库插件，`0` 表示不支持。这个头只表示构建能力，不表示插件已启用或已加载。

对应源码：`internal/pluginhost/support_cgo.go` 与 `support_nocgo.go` 通过 `//go:build cgo` 切换常量。**没有 CGO 的构建无法加载插件。**
