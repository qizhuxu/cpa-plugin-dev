# C ABI 契约

来源：`sdk/pluginabi/types.go`、`internal/pluginhost/rpc_schema.go`、`internal/pluginhost/abi.go`、`examples/plugin/simple/{go,c,rust}`。
本文件中的所有符号与常量均可在上述文件中逐字核对。

## 版本常量

| 常量 | 值 | 含义 |
|---|---|---|
| `ABIVersion` | `1` | 原生 C ABI 结构形状的版本，用于 `cliproxy_plugin_init` 的握手 |
| `SchemaVersion` | `6` | `plugin.register` 时协商的 RPC JSON 契约版本 |

`SchemaVersion` 的演进（`sdk/pluginabi/types.go` 注释）：

| 版本 | 变化 |
|---|---|
| 2 | 增加 request lifecycle 完成事件与主动终止请求 |
| 3 | 流式 payload chunk（`ChunkIndex >= 0`）上不再携带 `OriginalRequest` / `RequestBody` |
| 4 | 增加上游 WebSocket 响应事件观察 |
| 5 | 流式 payload chunk 上不再携带 `HistoryChunks` |
| 6 | 插件 Management API 的 JSON 响应不再做 HTML 实体转义 |

注册响应里返回较低的 `schema_version` 可以保留旧行为，代价是失去对应版本的新能力。

## 导出的符号：只有一个

**宿主只按名字查找一个符号：`cliproxy_plugin_init`。** 见 `internal/pluginhost/loader_windows.go` 的 `dll.FindProc("cliproxy_plugin_init")`。

另外三个函数**不是**导出符号，它们是插件在初始化时填进 `cliproxy_plugin_api` 结构体的函数指针：

```c
int cliproxy_plugin_init(const cliproxy_host_api* host, cliproxy_plugin_api* plugin);
```

插件在 `cliproxy_plugin_init` 里回填 `plugin->call`、`plugin->free_buffer`、`plugin->shutdown` 三个指针，宿主之后通过结构体调用它们。

实测三语言产物的导出表，可以印证这一点：

| 骨架 | 导出符号数 | 说明 |
|---|---|---|
| C 示例 | 1 | 源码里只有一处 `CLIPROXY_EXPORT`，就在 `cliproxy_plugin_init` 上 |
| Rust 示例 | 1 | 只有一处 `#[no_mangle] pub extern "C"` |
| Go 示例 | 4 | cgo 为了让 Go 函数能被取地址，把四个都导出成 C 符号。这是 cgo 的实现细节，不是契约要求 |

写 C 或 Rust 插件时只需要导出一个函数。写 Go 插件时四个 `//export` 指令都要有，否则 `C.cliproxyPluginCall` 这类表达式取不到地址，编译不过。

C 用 `__declspec(dllexport)`（Windows）或 `__attribute__((visibility("default")))`。Rust 用 `#[no_mangle] pub extern "C"`。Go 用 `//export` 且必须 `import "C"`，并在 `package main` 中留一个空的 `main()`。

## 宿主函数表

宿主通过 `cliproxy_plugin_init` 的第一个参数传入，插件应在初始化时保存 `host_ctx` 与 `call`。

```c
typedef struct { void* ptr; size_t len; } cliproxy_buffer;

typedef struct {
    uint32_t abi_version;
    void*    host_ctx;
    int  (*call)(void* host_ctx, const char* method, const uint8_t* request, size_t request_len, cliproxy_buffer* response);
    void (*free_buffer)(void* ptr, size_t len);
} cliproxy_host_api;
```

## 插件函数表

插件在 `cliproxy_plugin_init` 中回填。`abi_version` 必须填 `1`。

```c
typedef struct {
    uint32_t abi_version;
    int  (*call)(char* method, uint8_t* request, size_t request_len, cliproxy_buffer* response);
    void (*free_buffer)(void* ptr, size_t len);
    void (*shutdown)(void);
} cliproxy_plugin_api;
```

`cliproxy_plugin_init` 成功返回 `0`；`plugin` 指针为 `NULL` 时返回 `1`。

## 跨边界的只有方法名和字节数组

C ABI 不传递 Go interface、slice、map、channel、`context.Context` 或 Go `error`。请求与响应都是 JSON 文本序列化成字节数组传输。

原始字节字段在 JSON 中自动以 base64 表示。这包括：

- `AuthData.StorageJSON`
- `ExecutorRequest.OriginalRequest`、`ExecutorRequest.Payload`
- `ExecutorResponse.Payload`
- `ManagementRequest.Body`、`ManagementResponse.Body`
- `HTTPRequest.Body`、`HTTPResponse.Body`
- `ExecutorStreamChunk.Payload`、`HTTPStreamChunk.Payload`

因此 C 和 Rust 插件必须自带 base64 编解码；Go 插件由 `encoding/json` 自动处理 `[]byte`。

## 信封格式

成功：

```json
{ "ok": true, "result": { } }
```

失败：

```json
{ "ok": false, "error": { "code": "invalid_request", "message": "request is invalid" } }
```

`pluginabi.Error` 的字段：

| 字段 | JSON 键 | 说明 |
|---|---|---|
| `Code` | `code` | 机器可读错误码 |
| `Message` | `message` | 人类可读描述 |
| `Retryable` | `retryable` | 可选，标记可重试 |
| `HTTPStatus` | `http_status` | 可选，要暴露给客户端的 HTTP 状态码 |

Go 插件可直接调用 `pluginabi.NewErrorEnvelope(code, message, httpStatus...)` 构造错误信封。注意 Go 原生 `error` 对象无法跨越 C ABI，必须编码进 JSON。

## http_status 必须显式设置

省略 `http_status` 或设为 `0` 时，CPA 会把错误降级为 HTTP `500`（`server_error` / `internal_server_error`），客户端会误判为网关故障并退避重试。

显式设置后的映射：

| `http_status` | 客户端 type | 客户端 code |
|---|---|---|
| `401` | `authentication_error` | `invalid_api_key` |
| `403` | `permission_error` | `insufficient_quota` |
| `404` | `invalid_request_error` | `model_not_found` |
| `429` | `rate_limit_error` | `rate_limit_exceeded` |
| `>= 500` | `server_error` | `internal_server_error` |

非流式路径 `executor.execute` 与流式路径 `executor.execute_stream` 两处都要设置，否则异常分类行为不一致。

## 返回码与内存所有权

- `call` 返回 `0` 表示处理成功，非 `0` 表示失败。失败时仍应写入错误信封。
- 插件写入 `response` 的缓冲区由插件分配，宿主读取后调用插件的 `free_buffer` 释放。Go 用 `C.CBytes` 分配，`C.free` 释放。C 用 `malloc` / `free`。Rust 需用宿主可释放的分配器，参考示例使用 `libc` 分配。
- 宿主写入的回调响应缓冲区由宿主分配，插件读取后必须调用宿主的 `free_buffer` 释放。
- 未识别的 method 应返回 `unknown_method` 错误信封，而不是崩溃或返回空。

## 每个请求都带 host_callback_id

`internal/pluginhost/rpc_schema.go` 为所有回调类请求结构体嵌入了 `HostCallbackID string \`json:"host_callback_id,omitempty"\``。插件在嵌套调用宿主时转发该字段，宿主据此识别发起方，从而在嵌套模型执行中跳过同一插件的拦截器，避免递归。
