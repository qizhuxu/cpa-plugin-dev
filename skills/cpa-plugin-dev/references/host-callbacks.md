# 宿主回调

宿主回调是**插件调用宿主**，方向与能力相反。它让插件复用 CPA 已经处理好的代理、凭证、模型路由、日志与用量统计，而不必自己复制这些逻辑。

来源：`internal/pluginhost/host_callbacks.go`（19 个 method 的 dispatch）、`stream_bridge.go`、`auth_callbacks.go`、`sdk/pluginapi/types.go`。

## 全部 19 个回调

### HTTP 类

| method | 请求字段 | 响应字段 |
|---|---|---|
| `host.http.do` | `method`、`url`、`headers`、`body`、`wire_profile`、`operation_id` | `status_code`、`headers`、`body` |
| `host.http.do_stream` | 同上 | `status_code`、`headers`、`stream_id`、`chunks` |
| `host.http.operation_open` | `host_callback_id` | `operation_id` |
| `host.http.cancel` | `operation_id` | 无 |
| `host.http.stream_read` | `stream_id` | `payload`、`error`、`done` |
| `host.http.stream_close` | `stream_id` | 无 |

`headers` 是 `map[string][]string`。`body`、`payload` 是 base64 字节。`wire_profile` 可选，含 `http1_only`、`disable_auto_compression`、`header_profile`（控制请求头顺序与大小写）。

### 模型执行类

| method | 请求字段 | 响应字段 |
|---|---|---|
| `host.model.execute` | `entry_protocol`、`exit_protocol`、`model`、`stream`、`body`、`headers`、`query`、`alt`、`forced_provider`、`auth_id`、`proxy_url`、`path` | `status_code`、`headers`、`body` |
| `host.model.execute_stream` | 同上 | `status_code`、`headers`、`stream_id` |
| `host.model.stream_read` | `stream_id` | `payload`、`error`、`done` |
| `host.model.stream_close` | `stream_id` | 无 |

`proxy_url` 支持 `http`、`https`、`socks5`、`socks5h`，仅对本次执行生效。`path` 可覆盖请求路径，例如 `/v1/images/generations`。

### 执行器流桥

| method | 请求字段 | 响应字段 |
|---|---|---|
| `host.stream.emit` | `stream_id`、`payload`、`error` | 无 |
| `host.stream.close` | `stream_id`、`error` | 无 |

执行器插件用它向宿主已建立的流推送 chunk，或主动关闭流。

### 日志

| method | 请求字段 |
|---|---|
| `host.log` | `level`、`message`、`fields`（`map[string]any`） |

`level` 对应 logrus 级别。**不要输出密钥、token、原始凭证 JSON 或用户敏感请求体。**

### 凭证类

| method | 请求字段 | 响应字段 |
|---|---|---|
| `host.auth.list` | 无 | `files`，元素为 `HostAuthFileEntry` |
| `host.auth.get` | `auth_index` | `auth_index`、`name`、`path`、`json` |
| `host.auth.get_runtime` | `auth_index` | `auth`，为 `HostAuthFileEntry` |
| `host.auth.save` | `name`（必须以 `.json` 结尾）、`json` | `name`、`path` |

`host.auth.get` 读物理凭证 JSON 文件，`host.auth.get_runtime` 读运行时记录，两者不同。`HostAuthFileEntry` 字段很宽，含 `status`、`disabled`、`unavailable`、`runtime_only`、`source`、`priority`、`email`、`recent_requests` 等。

### 路由类

| method | 请求字段 | 响应字段 |
|---|---|---|
| `host.affinity.lookup` | `provider`、`model`、`session_id` | `status`、`auth_index`、`observed_at`、`disabled`、`unavailable` |
| `host.routing.reset_cooldown` | `auth_index` | `auth_index`、`models` |

`status` 取值：`bound`、`unbound`、`ambiguous`、`unsupported`。仅在 `bound` 时 `auth_index` 可用。

## 递归保护

插件从 `management.handle` 或其他宿主调用上下文中再次调用 `host.model.execute` / `host.model.execute_stream` 时，**必须转发请求中收到的 `host_callback_id`**。

宿主据此识别发起回调的插件，并在嵌套模型执行中跳过**同一个插件**的请求、响应与流式拦截器。其他已启用插件仍可处理这次嵌套请求。

不转发该字段会导致插件递归调用自己。

## 流式资源必须显式关闭

`host.http.do_stream` 与 `host.model.execute_stream` 返回 `stream_id`。读取完毕后调用对应的 `*_close`。

宿主可以在 RPC 作用域结束时清理一部分资源，但插件主动关闭能更快释放流资源，也更容易定位错误。

## 开发建议

- 插件自己的 HTTP 请求**优先走 `host.http.*`**，否则会绕过宿主代理、日志与传输策略。
- 需要发起模型请求时**优先走 `host.model.*`**，不要把宿主凭证复制进插件。
- 不要把读取凭证、写入凭证或执行特权动作的宿主回调直接暴露成未鉴权的资源 query 参数。面向用户的 UI 应使用同源受信任资源页加带管理密钥的 `/v0/management/...` 调用。
