# 阶段三：开发（基于 SDK 与 ABI 契约编码）

前置阅读：`references/abi-contract.md`、`references/capabilities.md`、`references/host-callbacks.md`。

**所有接口以源码为准。** Go 插件直接 import `sdk/pluginapi` 与 `sdk/pluginabi` 复用结构体，不要手抄字段名。

## 实现骨架（Go）

```go
package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef struct { void* ptr; size_t len; } cliproxy_buffer;

typedef int (*cliproxy_host_call_fn)(void*, const char*, const uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_host_free_fn)(void*, size_t);

typedef struct {
	uint32_t abi_version;
	void* host_ctx;
	cliproxy_host_call_fn call;
	cliproxy_host_free_fn free_buffer;
} cliproxy_host_api;

typedef int (*cliproxy_plugin_call_fn)(char*, uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_plugin_free_fn)(void*, size_t);
typedef void (*cliproxy_plugin_shutdown_fn)(void);

typedef struct {
	uint32_t abi_version;
	cliproxy_plugin_call_fn call;
	cliproxy_plugin_free_fn free_buffer;
	cliproxy_plugin_shutdown_fn shutdown;
} cliproxy_plugin_api;

extern int cliproxyPluginCall(char*, uint8_t*, size_t, cliproxy_buffer*);
extern void cliproxyPluginFree(void*, size_t);
extern void cliproxyPluginShutdown(void);
*/
import "C"

import (
	"encoding/json"
	"unsafe"

	"github.com/router-for-me/CLIProxyAPI/v8/sdk/pluginabi"
	"github.com/router-for-me/CLIProxyAPI/v8/sdk/pluginapi"
)

func main() {}

//export cliproxy_plugin_init
func cliproxy_plugin_init(host *C.cliproxy_host_api, plugin *C.cliproxy_plugin_api) C.int {
	if plugin == nil {
		return 1
	}
	plugin.abi_version = C.uint32_t(pluginabi.ABIVersion)
	plugin.call = C.cliproxy_plugin_call_fn(C.cliproxyPluginCall)
	plugin.free_buffer = C.cliproxy_plugin_free_fn(C.cliproxyPluginFree)
	plugin.shutdown = C.cliproxy_plugin_shutdown_fn(C.cliproxyPluginShutdown)
	return 0
}
```

`host` 指针要在初始化时保存下来（Go 侧用包级变量存 `host.call` 与 `host.host_ctx`），后续调用宿主回调时要用。

## method dispatch

一个 `switch` 覆盖声明的全部 method，**default 分支必须返回 `unknown_method` 错误信封**，不要 panic。

```go
func handleMethod(method string, request []byte) ([]byte, error) {
	switch method {
	case pluginabi.MethodPluginRegister, pluginabi.MethodPluginReconfigure:
		return okEnvelope(registration())
	case pluginabi.MethodRequestNormalize:
		return handleNormalize(request)
	// ... 其余声明的 method
	default:
		return errorEnvelope("unknown_method", "unknown method: "+method), nil
	}
}
```

`plugin.register` 与 `plugin.reconfigure` 共用同一个处理函数即可，返回同样的注册响应。

## 信封处理

成功与失败两个构造函数，所有 method 都通过它们返回：

```go
type envelope struct {
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *pluginabi.Error `json:"error,omitempty"`
}

func okEnvelope(v any) ([]byte, error) {
	raw, errMarshal := json.Marshal(v)
	if errMarshal != nil {
		return nil, errMarshal
	}
	return json.Marshal(envelope{OK: true, Result: raw})
}
```

失败时**优先用 SDK 提供的构造函数**，它会正确处理 `http_status`：

```go
rawEnvelope, errMarshal := pluginabi.NewErrorEnvelope("insufficient_quota", "plan limit reached", http.StatusForbidden)
```

## 写响应缓冲区

```go
func writeResponse(response *C.cliproxy_buffer, raw []byte) {
	if response == nil || len(raw) == 0 {
		return
	}
	ptr := C.CBytes(raw)
	if ptr == nil {
		return
	}
	response.ptr = ptr
	response.len = C.size_t(len(raw))
}
```

缓冲区用 `C.CBytes` 分配，由宿主的 `cliproxyPluginFree` 释放。**不要用 Go 分配的内存交给 C 释放。**

## 各能力的实现要点

| 能力 | 要点 |
|---|---|
| `executor` | 四个 method 都要实现。`execute` 与 `execute_stream` 的失败路径都要设 `http_status`。上游调用走 `host.http.*` 或 `host.model.*`，不要自己发 HTTP |
| `executor.execute_stream` | 返回 `{headers, chunks}`，chunk 的 `Payload` 是 base64 字节 |
| `auth_provider` | 五个 method 都要实现。`auth.parse` 用 `Handled` 表达"这不是我的凭证"；`auth.login.poll` 用 `Status` 表达 `pending` / `success` / `error` |
| `frontend_auth_provider` | 返回 `Authenticated: false` 表示拒绝，不要返回错误信封 |
| `scheduler` | 返回 `Handled: false` 表示不参与本次调度。拒绝调度用 `Reject: true` 加 `RejectReason` / `RejectCode` |
| `model_router` | `Handled: true` 时 `TargetKind` 必须是 `self`、`executor`、`provider` 之一。`executor` 时 `Target` 填插件 ID，`provider` 时填 provider 键 |
| `request_interceptor` | 请求体视为只读，改动必须通过 `RequestInterceptResponse.Body` 返回。终止请求用 `Terminate: true` 加 `StatusCode`（无效值默认 403） |
| `response_stream_interceptor` | `ChunkIndex == -1` 是 header 初始化调用，`>= 0` 是 payload chunk。丢弃 chunk 用 `DropChunk: true` |
| `request_lifecycle_plugin` | 异步接收终态事件，`Outcome` 取值 `succeeded` / `failed` / `rejected` / `canceled`。**不要在这里做耗时操作** |
| `thinking_applier` | 收到的是已解析并归一化的 `Config`，不要再解析原始后缀 |
| `usage_plugin` | 只读观察，无返回值。失败不要影响请求 |
| `management_api` | 敏感操作放 `routes`（需管理密钥），只读展示放 `resources`（无鉴权）。见 `pitfalls.md` 第 8 条 |
| `quota_provider` | `DescribeQuota` 声明支持的 provider 键，`FetchQuota` 返回归一化的 `groups` / `summary` |

## 常见编码错误

| 错误 | 后果 | 正确做法 |
|---|---|---|
| 返回 Go `error` 对象 | 无法跨越 C ABI，宿主收到空响应 | 编码成错误信封 |
| 错误信封不设 `http_status` | 全部降级为 HTTP 500，客户端退避重试 | 按 `abi-contract.md` 的映射表显式设置 |
| 声明了能力但 default 分支没覆盖其 method | 宿主调用时收到 `unknown_method` | dispatch 覆盖声明的全部 method |
| 用 Go 内存写 `response.ptr` | 宿主用 C `free` 释放时崩溃 | 用 `C.CBytes` |
| 嵌套调用 `host.model.*` 时不转发 `host_callback_id` | 插件递归调用自己 | 原样转发该字段 |
| 流式资源不关闭 | 流资源泄漏 | 读完调 `*_stream_close` |
| `schema_version` 返回 0 | 每 chunk 都带完整请求体副本，开销明显 | 返回 6 |
| 日志里输出凭证 | 密钥泄漏 | 只记结构，不记值 |
| 未处理 `plugin.reconfigure` | 配置变更后插件仍用旧配置 | 与 `plugin.register` 共用处理函数 |
| 在 `plugin.register` 里做重活 | 阻塞宿主启动 | 注册只返回元数据与能力声明 |

## 并发与状态

- 插件与宿主同进程，多个请求会并发进入 `cliproxyPluginCall`。共享状态必须加锁或用原子操作。
- 包级可变状态在 `plugin.reconfigure` 时要能安全更新。
- `plugin.quiesce` 后不应再启动新的长任务；`plugin.shutdown` 里释放资源。
- 插件退出进程等同于宿主退出。**不要调用 `os.Exit`、`log.Fatal` 或 Rust 的 `std::process::exit`。**

## 阶段三交付物

- 通过 `make` 或 `scripts/build-plugin.sh` 可构建的动态库
- dispatch 覆盖全部声明的 method
- 错误路径全部设置 `http_status`
- 日志中无凭证
