# 阶段四：测试（本地实例与管理 API 验证）

前置阅读：`references/config-discovery.md`、`docs/management-api-v8.zh.md`。

目标：证明插件被宿主**加载、注册并生效**，而不只是构建成功。

## 第零步：确认二进制支持插件

插件依赖 CGO。先确认目标二进制具备加载能力：

```bash
curl -s -D - -o /dev/null http://127.0.0.1:8317/v8/management/plugins \
  -H "Authorization: Bearer $MANAGEMENT_KEY" | grep -i "CPA-SUPPORT-PLUGIN"
```

`1` 表示支持，`0` 表示该二进制没有 CGO，无论怎么配置都加载不了插件。

本机已有的测试实例：`CPA相关/cpa-test/cli-proxy-api.exe`，配套 `config.yaml` 与 `auths/`。该二进制的探测结果为支持。

## 第一步：启动实例

```bash
cd CPA相关/cpa-test
./cli-proxy-api.exe --config config.yaml
```

默认监听 `8317`。配置文件里的 `plugins.enabled` 初始为 `false`，需要打开。

## 第二步：打开插件开关

`plugins.enabled` 与单插件 `enabled` 是**两个独立开关**，必须同时为真：

```yaml
plugins:
  enabled: true          # 全局，默认 false
  dir: "plugins"
  configs:
    <plugin-id>:
      enabled: true      # 单插件，未写时按 false 处理
      priority: 1
```

改完由配置热重载生效，或通过管理接口：

```bash
# 只改单插件开关，不会动全局 plugins.enabled
curl -X PUT http://127.0.0.1:8317/v8/management/config/plugins/configs/<plugin-id>/enabled \
  -H "Authorization: Bearer $MANAGEMENT_KEY" \
  -H "Content-Type: application/json" -d 'true'
```

全局 `plugins.enabled` 从 `false` 变 `true` 需要重新扫描目录，稳妥做法是重启。

## 第三步：确认已注册

```bash
curl -s http://127.0.0.1:8317/v8/management/plugins \
  -H "Authorization: Bearer $MANAGEMENT_KEY"
```

四个状态字段含义不同：

| 字段 | 含义 | 期望值 |
|---|---|---|
| `plugins_enabled` | 全局开关 | `true` |
| `enabled` | 单插件配置开关 | `true` |
| `registered` | 动态库已加载并完成注册 | `true` |
| `effective_enabled` | 三者同时满足 | `true` |

**只有 `registered` 与 `effective_enabled` 同时为 `true` 才算真正生效。** 只看 `enabled` 会把"配置开了但库没加载"误判为成功。

响应里还会返回 `path`，用它核对加载的是不是刚构建的那个文件。

## 第四步：按能力验证

| 能力 | 验证方式 |
|---|---|
| `management_api` 的 `routes` | 用管理密钥请求注册的 `/v0/management/...` 路径 |
| `management_api` 的 `resources` | 浏览器打开 `/v0/resource/plugins/<plugin-id>/<path>`，**不需要管理密钥** |
| `command_line_plugin` | 启动时加 `--help`，确认插件注册的参数出现在帮助里 |
| `model_registrar` / `model_provider` | 请求 `/v1/models`，确认插件提供的模型 ID 在列表中 |
| `executor` | 向插件负责的模型发一次真实请求，同时看非流式与流式两条路径 |
| `auth_provider` | 走 `/v8/management/oauth/auth-url?provider=<provider>`，确认插件被调用；再看凭证列表 |
| `frontend_auth_provider` | 用错误凭证发请求，确认被拒；用正确凭证确认放行 |
| `scheduler` | 配多个凭证，确认选择结果符合插件逻辑；验证 `Reject` 时请求被拒 |
| `model_router` | 请求目标模型，确认被路由到声明的执行器 |
| translator / normalizer / interceptor | 发一次请求，抓请求体与响应体，逐字段比对改写结果 |
| `response_stream_interceptor` | 发流式请求，确认 header 初始化调用与每个 chunk 都到达；验证 `DropChunk` 生效 |
| `thinking_applier` | 带 thinking 参数请求，确认 payload 里出现插件写入的字段 |
| `usage_plugin` | 发请求后查用量记录，确认插件收到 |
| `quota_provider` | `GET /v8/management/plugins/<id>/quota?auth_index=<index>` |
| `websocket_response_observer` | 走 WebSocket 路径发请求，确认事件到达 |

错误路径也要测：故意让上游返回 401 / 403 / 429，确认客户端收到的状态码与 `type` / `code` 符合 `abi-contract.md` 的映射表，**而不是全部变成 500**。

## 第五步：修改后重新加载

Windows 会锁住已加载的 DLL，宿主用影子副本规避，但**替换磁盘文件不会影响正在运行的实例**。

```bash
# 定向卸载：删除本地动态库与保存的配置
curl -X DELETE http://127.0.0.1:8317/v8/management/plugins/<plugin-id> \
  -H "Authorization: Bearer $MANAGEMENT_KEY"
```

返回 `409` 且带 `restart_required: true` 时只能重启服务。

## 常见失败诊断

| 现象 | 原因 | 排查 |
|---|---|---|
| `registered: false` | 库没被加载 | 核对文件名是否为插件 ID、扩展名是否匹配平台、`plugins.dir` 路径是否正确 |
| `registered: true` 但 `effective_enabled: false` | 某个开关没开 | 同时检查 `plugins_enabled` 与 `enabled` |
| 所有请求返回 `500 internal_server_error` | 错误信封没设 `http_status` | 见 `pitfalls.md` 第 4 条 |
| 请求返回 `auth_not_found`（503） | provider 没有可用凭证，宿主在调用执行器之前就拒绝了 | 执行器插件同样需要凭证；见 `pitfalls.md` 第 14 条 |
| 宿主调用某 method 收到 `unknown_method` | 声明了能力但 dispatch 没覆盖 | 见 `phase-3-develop.md` 的常见错误表 |
| 插件加载后进程崩溃 | 内存所有权错误，或用 Go 内存交给 C 释放 | 用 `C.CBytes` 分配响应缓冲区 |
| 插件递归调用自己 | 嵌套回调没转发 `host_callback_id` | 见 `host-callbacks.md` |
| 管理路由访问不到 | 与宿主已有路由重名，被静默跳过 | 换一个路径前缀 |
| 改了代码但行为没变 | 旧实例仍在运行 | 走卸载接口或重启 |
| 请求量一大就出错 | 共享状态没加锁 | 加锁或用原子操作 |

## 用脚本验证

```bash
scripts/verify-plugin.sh <plugin-id> [管理密钥] [管理端口]
```

脚本依次做：探测二进制插件支持能力、读取 `GET /v8/management/plugins`、比对目标插件的四个状态字段、打印 `path` 与注册的菜单，并在失败时给出对应的排查建议。

## 阶段四交付物

- 一份验证记录：四个状态字段的实际值、`path`、按能力跑过的测试项与结果
- 错误路径的状态码映射确认
- 已知未覆盖项清单
