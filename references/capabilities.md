# 能力清单（权威）

来源：`internal/pluginhost/rpc_schema.go` 的 `rpcCapabilities` 结构体。这是宿主真正解析的 JSON 键，**优先于任何文档**。

`plugin.register` 的响应中 `capabilities` 对象共 **27 个键**：24 个布尔能力开关，3 个执行器修饰字段。

## 布尔能力开关（24 个）

| # | JSON 键 | 对应 method | 作用 |
|---|---|---|---|
| 1 | `model_registrar` | `model.register` | 注册静态模型元数据 |
| 2 | `model_provider` | `model.static`、`model.for_auth` | 提供静态模型或按凭证提供模型 |
| 3 | `auth_provider` | `auth.identifier`、`auth.parse`、`auth.login.start`、`auth.login.poll`、`auth.refresh` | 解析、登录、轮询、刷新插件自有凭证 |
| 4 | `frontend_auth_provider` | `frontend_auth.identifier`、`frontend_auth.authenticate` | 在代理处理前认证客户端请求 |
| 5 | `frontend_auth_provider_exclusive` | 无独立 method | 修饰符，被选中后成为唯一请求认证方式；仅在同时声明 `frontend_auth_provider` 时生效 |
| 6 | `scheduler` | `scheduler.pick` | 在候选凭证中选择，或委托内置调度器 |
| 7 | `scheduler_across_priorities` | 无独立 method | 修饰符，让 `Candidates` 包含全部优先级层，默认只给最高可用层 |
| 8 | `model_router` | `model.route` | 在 provider / auth 选择前路由请求 |
| 9 | `executor` | `executor.identifier`、`executor.execute`、`executor.execute_stream`、`executor.count_tokens`、`executor.http_request` | 直接执行上游请求 |
| 10 | `request_translator` | `request.translate` | 规范请求转上游协议 |
| 11 | `request_normalizer` | `request.normalize` | 规整进入执行链路的请求 |
| 12 | `request_interceptor` | `request.intercept_before`、`request.intercept_after` | 选凭证前后改写执行请求 |
| 13 | `request_lifecycle_plugin` | `request.complete` | 异步接收每个已拦截请求的终态事件 |
| 14 | `response_translator` | `response.translate` | 规范响应转客户端协议 |
| 15 | `response_before_translator` | `response.normalize_before` | 原生转换前规整响应 |
| 16 | `response_after_translator` | `response.normalize_after` | 转换后规整响应 |
| 17 | `response_interceptor` | `response.intercept_after` | 改写成功的非流式响应 |
| 18 | `response_stream_interceptor` | `response.intercept_stream_chunk` | 改写流式响应 chunk |
| 19 | `websocket_response_observer` | `websocket.response_event` | 观察上游 WebSocket 响应事件 |
| 20 | `thinking_applier` | `thinking.identifier`、`thinking.apply` | 应用已验证的 thinking 配置 |
| 21 | `usage_plugin` | `usage.handle` | 接收完成后的用量记录 |
| 22 | `command_line_plugin` | `command_line.register`、`command_line.execute` | 注册并处理插件自有命令行参数 |
| 23 | `management_api` | `management.register`、`management.handle` | 注册管理路由与浏览器资源 |
| 24 | `quota_provider` | `quota.identifier`、`quota.describe`、`quota.fetch`、`quota.reset` | 向管理端暴露凭证配额与账单 |

## 执行器修饰字段（3 个）

| JSON 键 | 类型 | 说明 |
|---|---|---|
| `executor_model_scope` | 字符串 | `both`（默认）、`static`、`oauth` |
| `executor_input_formats` | 字符串数组 | 执行器直接接受的请求协议，**至少声明一个** |
| `executor_output_formats` | 字符串数组 | 执行器直接产出的响应协议，**至少声明一个** |

空 `executor_model_scope` 按 `both` 处理以保持向后兼容。声明了 `executor` 却没声明输入或输出格式是无效的。

## 注册响应结构

```json
{
  "ok": true,
  "result": {
    "schema_version": 6,
    "metadata": {
      "Name": "example-provider",
      "Version": "0.1.0",
      "Author": "author",
      "GitHubRepository": "https://github.com/author/example-provider",
      "Logo": "https://example.com/logo.png",
      "ConfigFields": [
        {
          "Name": "mode",
          "Type": "enum",
          "EnumValues": ["safe", "fast"],
          "Description": "Execution mode."
        }
      ]
    },
    "capabilities": {
      "request_normalizer": true,
      "management_api": true
    }
  }
}
```

`Metadata` 字段名是 **Go 导出名风格**（`Name`、`Version`、`GitHubRepository`、`ConfigFields`），而 `capabilities` 的键是 **snake_case**。这个混用在 `rpc_schema.go` 与 `pluginapi.Metadata` 中是确定的，不要统一。

`ConfigField.Type` 取值：`string`、`number`、`integer`、`boolean`、`enum`、`array`、`object`。`enum` 必须同时给 `EnumValues`。

`ConfigFields` 只供管理端渲染配置表单，**不替代插件自身的校验**。插件仍应在 `plugin.register` 与 `plugin.reconfigure` 中验证自己关心的字段。

## 生命周期方法（不属于 capabilities）

| method | 方向 | 作用 |
|---|---|---|
| `plugin.register` | 宿主调插件 | 首次加载，读取元数据、配置字段与能力声明 |
| `plugin.reconfigure` | 宿主调插件 | 配置变更后重新传入该插件配置 |
| `plugin.quiesce` | 宿主调插件 | 卸载前的静默通知 |
| `plugin.shutdown` | 宿主调插件 | 释放资源 |

`plugin.register` 与 `plugin.reconfigure` 的请求都含 `config_yaml`（base64 字节），另有 `schema_version`。

## 声明原则

**只声明真正实现的能力。** 宿主按声明调用；声明了却返回错误会污染该阶段的所有请求。多插件处理同一阶段时高优先级先执行，宿主总体规则是原生逻辑优先、插件补齐缺口。
