# 阶段二：产出计划（脚手架与方案生成）

目标：把阶段一的能力清单变成可构建的插件目录。**这一阶段的完成标志是能构建出动态库。**

## 语言选型

| 语言 | 适用 | 构建命令 | 注意 |
|---|---|---|---|
| **Go** | 默认选择 | `go build -buildmode=c-shared` | 需要 CGO；`[]byte` 的 base64 由 `encoding/json` 自动处理；社区插件几乎全是 Go |
| **C** | 最小依赖、嵌入既有 C 代码 | CMake 构建 `SHARED` 库 | 必须自己实现 base64 与 JSON 解析 |
| **Rust** | 需要 Rust 生态 | `cargo build --release`，`crate-type = ["cdylib"]` | 必须自己实现 base64 与 JSON 解析 |

**默认选 Go。** 理由：JSON 与 base64 由标准库处理，`sdk/pluginapi` 与 `sdk/pluginabi` 可直接 import 复用全部结构体定义，示例最完整，社区事实标准。

选 C 或 Rust 的唯一理由是插件要复用的既有代码是那个语言。选之前先确认能接受手写 base64 与 JSON 编解码的成本。

## 用脚手架生成目录

```bash
scripts/new-plugin.sh <plugin-id> [go|c|rust] [输出目录]
```

脚本从 `assets/skeleton-{go,c,rust}/` 复制骨架，替换占位符为真实插件 ID，并生成符合 `[A-Za-z0-9][A-Za-z0-9._-]{0,127}` 的目录。

**插件 ID 规则：** 来自动态库文件名去掉扩展名，必须以字母或数字开头，只能含字母、数字、`.`、`_`、`-`，最长 128 字符。ID 同时是配置键和资源路径的一部分，定下来后不要改。

## 目录布局

Go 插件的推荐布局，与社区 `cpa-plugin-*` 仓库一致：

```
<plugin-id>/
├── go.mod                 module 名可独立，需 require CLIProxyAPI/v8
├── main.go                导出符号与 method dispatch
├── internal/
│   ├── capability/        各能力的实现，一个能力一个文件
│   └── envelope/          信封编解码与错误构造
├── Makefile               构建目标
├── config.example.yaml    配置示例，字段与 ConfigFields 一致
├── README.md              安装与配置说明
└── registry.json          发布用（见 packaging.md）
```

单能力插件可以省略 `internal/`，全部写在 `main.go` 里。能力超过两个就应该拆。

## 构建

三个语言的构建命令，与 `examples/plugin/Makefile` 一致：

```bash
# Go
cd <plugin-id>/go && go build -buildmode=c-shared -o <plugin-id>.so .

# C
cmake -S <plugin-id>/c -B build/<plugin-id>
cmake --build build/<plugin-id>

# Rust
cd <plugin-id>/rust && cargo build --release --locked
```

产物扩展名按平台：Linux/FreeBSD `.so`，macOS `.dylib`，Windows `.dll`。

用仓库脚本：

```bash
scripts/build-plugin.sh <插件目录> [go|c|rust]
```

脚本自动识别平台扩展名并输出到 `bin/`。

## Go 插件的 go.mod

必须能 import 到 v8 的 SDK：

```
require github.com/router-for-me/CLIProxyAPI/v8 v8.x.x
```

导入路径是 **v8**。示例 README 中出现的 v7 是过期内容，见 `pitfalls.md`。

`go build -buildmode=c-shared` 需要 CGO 可用（需要 C 工具链）。构建产出的 `.h` 文件不需要分发，可以删掉。

**Windows 上先验证工具链。** `-buildmode=c-shared` 会调用 `PATH` 上的 `gcc`，而某些 MinGW 发行版（实测 TDM-GCC 10.3.0）会链接出 Windows 拒绝加载的映像，报 `ERROR_BAD_EXE_FORMAT`。构建完立刻做一次加载测试，不要等到配好 CPA 才发现：

```bash
# 能成功返回才算工具链可用
python -c "import ctypes; ctypes.WinDLL(r'<构建产物绝对路径>')"
```

失败就换 MinGW-W64 官方构建或 MSVC。完整排查见 `pitfalls.md` 第 13 条。

## 放置位置

构建产物放进 CPA 的插件目录，按搜索优先级选择：

```
<plugins.dir>/<GOOS>/<GOARCH>/<plugin-id>.<ext>    优先级最高
<plugins.dir>/<GOOS>/<GOARCH>-<variant>/<plugin-id>.<ext>
<plugins.dir>/<plugin-id>.<ext>                     优先级最低
```

单平台开发直接放 `plugins/` 根目录即可。

## 方案文档

进入编码前，产出一份简短方案，包含：

1. 插件 ID 与语言
2. 声明的能力清单（JSON 键）
3. 需要实现的 method 清单
4. 需要调用的宿主回调清单
5. 配置字段表
6. 构建产物路径与放置位置
7. 阶段四要跑的验证项

这份方案就是阶段三的实现清单。

## 阶段二交付物

- 可构建的插件目录骨架
- 能成功执行一次构建，产出动态库
- 方案文档
