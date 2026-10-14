# 阶段一：定制要求（需求解析与配置）

目标：把一个模糊的"我想让 CPA 做 X"变成一份明确的能力清单和配置草案。**这一阶段不写代码。**

## 第一步：把需求映射到能力

CPA 的插件能力分成五组。按用户描述先定位到组，再定位到具体能力。

| 用户想做的事 | 组 | 能力 | 典型场景 |
|---|---|---|---|
| 接入一个 CPA 不支持的上游 | 入口 | `executor`（必需）+ `model_provider` 或 `model_registrar` | 新厂商、私有网关、本地模型 |
| 用非标准方式登录某个上游 | 入口 | `auth_provider` | 自定义 OAuth、设备码、导入式凭证 |
| 校验客户端带来的自定义凭证 | 入口 | `frontend_auth_provider` | 自建 API key 体系 |
| 改变多个凭证之间的选择逻辑 | 入口 | `scheduler` | 按业务规则分配、拒绝调度 |
| 把某类请求改道到别的执行器 | 入口 | `model_router` | 特定模型走特例通道 |
| 改请求内容 | 请求 | `request_translator` / `request_normalizer` / `request_interceptor` | 参数改写、字段注入、拒绝对话 |
| 改响应内容 | 响应 | `response_translator` / `response_before_translator` / `response_after_translator` / `response_interceptor` / `response_stream_interceptor` | 字段改写、chunk 过滤、格式适配 |
| 控制思考预算 | 扩展 | `thinking_applier` | 厂商私有 reasoning 字段 |
| 记录用量、做账单 | 扩展 | `usage_plugin` | 计费、审计 |
| 增加命令行参数 | 扩展 | `command_line_plugin` | 导入凭证、一次性运维命令 |
| 增加管理页面或诊断接口 | 扩展 | `management_api` | 配置面板、状态页 |
| 展示凭证余额与配额 | 扩展 | `quota_provider` | 额度图表 |

## 第二步：区分"入口能力"与"加工能力"

这一步决定实现的复杂度。

**入口能力**（`executor`、`auth_provider`、`frontend_auth_provider`、`scheduler`、`model_router`）参与路由决策。声明它们意味着插件会被要求在关键路径上做决定，`Handled: false` 必须能正确表达"我不处理这次"。

**加工能力**（各类 translator / normalizer / interceptor / thinking）只改写数据，不改变路由。它们更安全，出错影响面也更小。

**优先选加工能力。** 只有当现有加工能力无法表达需求时才用入口能力。

## 第三步：确认是否需要 executor

只有当请求要发往 CPA 还不认识的上游时，才需要 `executor`。如果只是改造已有上游的请求或响应，用 translator 或 normalizer。

声明 `executor` 时必须同时给出：

```json
{
  "executor": true,
  "executor_model_scope": "both",
  "executor_input_formats": ["chat-completions"],
  "executor_output_formats": ["chat-completions"]
}
```

`executor_input_formats` 与 `executor_output_formats` 各至少一个，缺失即无效。

## 第四步：设计插件自有配置

插件自有字段写在 `plugins.configs.<pluginID>` 下，与宿主拥有的 `enabled`、`priority` 平级。宿主原样透传，插件在 `plugin.register` / `plugin.reconfigure` 的 `config_yaml` 中读取。

**先定字段，再写代码。** 每个字段要回答：

| 问题 | 为什么重要 |
|---|---|
| 默认值是什么 | 用户不写这个字段时插件必须能工作 |
| 类型是什么 | 决定 `ConfigFields` 里 `Type` 填什么 |
| 是否是枚举 | 是枚举就同时给 `EnumValues`，管理端才能渲染下拉框 |
| 删掉它会发生什么 | 字段要保持向后兼容，删除时需兼容旧配置 |

`ConfigField.Type` 取值：`string`、`number`、`integer`、`boolean`、`enum`、`array`、`object`。

`ConfigFields` 只是给管理端渲染表单用，**不替代插件自身的校验**。`plugin.register` 与 `plugin.reconfigure` 里仍要验证自己关心的字段，非法值要明确报错而不是静默取默认值。

## 第五步：定优先级

`priority` 决定同一阶段多插件的执行顺序，**高优先级先处理**。

参考量级：

| 场景 | 建议 |
|---|---|
| 纯观察类（`usage_plugin`、`websocket_response_observer`） | 低优先级，不参与决策 |
| 加工类（translator / normalizer） | 中等 |
| 决策类（`scheduler`、`model_router`、`request_interceptor`） | 较高，确保在加工前生效 |
| 需要最先看到请求的 | 最高 |

## 阶段一交付物

1. 一份能力清单：声明哪些能力，各自的 JSON 键与对应 method
2. 一份配置草案：字段名、类型、默认值、是否枚举
3. 一句优先级理由
4. 明确的不做清单：哪些能力**不**声明，以及为什么

确认这四项之后再进入阶段二。**能力声明一旦写错，后续所有阶段都要返工。**
