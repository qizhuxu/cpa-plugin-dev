# 骨架资产

三语言的最小可构建起点。**所有 ABI 结构、符号名与信封格式均取自官方示例，没有一处是推测的。**

| 目录 | 来源 | 说明 |
|---|---|---|
| `skeleton-go/` | 改写自 `examples/plugin/simple/go/main.go` | cgo 前导、导出符号、init 与响应缓冲区处理逐字沿用；能力集合被**裁剪为单个** `request_normalizer`，并加入 `__PLACEHOLDER__` 供替换。**默认推荐路径。** |
| `skeleton-c/` | 逐字复制 `examples/plugin/simple/c/` | 保留官方全部能力演示（kitchen sink）。 |
| `skeleton-rust/` | 逐字复制 `examples/plugin/simple/rust/` | 同上。 |

## 为什么 Go 骨架被裁剪

官方 `simple` 示例为了演示而**声明了全部能力**。照抄它会得到一个声明了很多能力却只实现了一部分的插件，宿主会调用那些没有实现的 method 并收到 `unknown_method`。

Go 骨架因此只声明 `request_normalizer` 一个加工能力，并在 `handleMethod` 中实现它。要加能力时：

1. 在 `registration()` 的 `capabilities` 里加对应的 JSON 键（键名见 `references/capabilities.md`）
2. 在 `handleMethod` 的 `switch` 里加该能力对应的全部 method
3. 补上错误路径的 `http_status`

**一次只加一个能力，加完就跑一次 `references/phase-4-test.md` 的验证。**

## C 与 Rust 骨架是完整的官方示例

它们保留全部能力演示，用途不同：

- 作为**参考实现**，看某个 method 的请求/响应长什么样
- 作为 C / Rust 插件的起点，但**必须先把不需要的能力从注册响应里删掉**

两个骨架都自带 base64 与 JSON 编解码实现（`base64_encode` / `base64_decode` / `extract_json_string` / `json_escape`），因为 C ABI 只传字节数组，原始字节字段在 JSON 中以 base64 表示，这部分在 C 和 Rust 里没有标准库可用。

## 占位符

Go 骨架中的占位符，由 `scripts/new-plugin.sh` 替换：

| 占位符 | 含义 |
|---|---|
| `__PLUGIN_ID__` | 插件 ID，同时是动态库文件名、配置键、资源路径段 |
| `__AUTHOR__` | 作者或组织名 |
| `__REPOSITORY__` | 仓库 URL，形如 `https://github.com/{owner}/{repo}` |
| `__PROVIDER_KEY__` | 插件对外声明的 provider 键 |

C 与 Rust 骨架中的示例插件 ID（`example-simple-c` / `example-simple-rust`）需要手工替换，`new-plugin.sh` 会做批量替换。

## 构建验证状态

| 骨架 | 是否实测构建 | 结果 |
|---|---|---|
| `skeleton-go` | 是 | 对本地 v8 源码构建成功，装载进 CPA 8.0.23 后 `registered` 与 `effective_enabled` 均为 true |
| `skeleton-rust` | 是 | `cargo build --release --locked` 成功，产出 137 KB cdylib，可加载，导出 `cliproxy_plugin_init` |
| `skeleton-c` | 是 | `build-plugin.sh` 在缺少 `cmake` 时自动退回直接编译（骨架是单文件），构建成功，可加载，导出符号为 `cliproxy_plugin_init` 一个 |

三个骨架的构建都已实测。`build-plugin.sh` 的 C 分支先找 `cmake`，找不到就退回直接编译单文件，两条路径产出的库都实测可加载。

## 构建

```bash
scripts/build-plugin.sh <插件目录> [go|c|rust]
```

或手工：

```bash
# Go
go build -buildmode=c-shared -o <plugin-id>.so .

# C（有 cmake）
cmake -S . -B build && cmake --build build

# C（没有 cmake）
gcc -shared -fPIC -O2 -o <plugin-id>.so src/plugin.c

# Rust
cargo build --release --locked
```
