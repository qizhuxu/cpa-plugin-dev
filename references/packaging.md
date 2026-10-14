# 发布：Release 资产与插件商店

来源：`docs/plugin-development.zh.md`（官方《插件开发》文档的商店发布格式一节）。

## Release 资产命名

每个平台的产物打成一个 zip，命名固定：

```
<pluginID>_<version>_<goos>_<goarch>.zip
checksums.txt
```

示例：

```
example-provider_0.1.0_linux_amd64.zip
example-provider_0.1.0_darwin_arm64.zip
example-provider_0.1.0_windows_amd64.zip
checksums.txt
```

GitHub release tag 可以是 `v0.1.0`，宿主会去掉前导 `v` 后校验版本。

## zip 内部结构

**动态库必须直接位于 zip 根目录，不能放在子目录里。**

```
example-provider.dll          <- 正确
```

```
dist/example-provider.dll     <- 错误，宿主找不到
```

## checksums.txt

常见 sha256 格式，两列之间两个空格：

```
<sha256>  example-provider_0.1.0_darwin_arm64.zip
<sha256>  example-provider_0.1.0_linux_amd64.zip
```

宿主下载 release 资产后会**先校验 checksums.txt**，再卸载旧实例、写入新文件、触发配置热重载。

生成命令：

```bash
cd dist && sha256sum *.zip > checksums.txt
```

Windows 上用 `certutil -hashfile <file> SHA256` 逐个生成。

## registry.json

官方 registry 仓库：`router-for-me/CLIProxyAPI-Plugins-Store`。它**只维护 registry.json，不托管二进制**，插件源码、release、checksums 都留在作者自己的仓库。

```json
{
  "schema_version": 1,
  "plugins": [
    {
      "id": "example-provider",
      "name": "Example Provider",
      "description": "Adds example provider support.",
      "author": "author-name",
      "version": "0.1.0",
      "repository": "https://github.com/author-name/example-provider",
      "logo": "https://example.com/logo.png",
      "homepage": "https://example.com",
      "license": "MIT",
      "tags": ["provider"]
    }
  ]
}
```

要求：

| 字段 | 约束 |
|---|---|
| `schema_version` | 必须是 `1` |
| `id` | 必填，全局唯一 |
| `name` | 必填 |
| `description` | 必填 |
| `author` | 必填 |
| `repository` | 必填，必须是 `https://github.com/{owner}/{repo}` 形式 |
| `version` | 可选，仅作展示兜底；**真正安装的版本来自 GitHub latest release tag** |

因为安装版本取自 latest release，**发布新版本不需要改 registry**。改了 `version` 字段也不会改变实际下载的版本。

## 第三方 registry

除官方源外可以追加自己的：

```yaml
plugins:
  store-sources:
    - "https://example.com/cliproxyapi-plugins/registry.json"
```

官方源始终包含。同一个插件 ID 在多个源出现时，安装时用 `?source=<source-id>` 指定来源。

私有 registry 需要认证时用 `plugins.store-auth`，密钥从环境变量读取：

```yaml
plugins:
  store-auth:
    - match: "https://plugins.example.com/bearer/"
      apply-to: ["registry", "artifact"]
      type: "bearer"
      token-env: "CLIPROXY_PLUGIN_STORE_TOKEN"
```

`type` 支持 `bearer`、`basic`、`header`、`github-token`。

## 安装与更新

```bash
# 安装或更新，会自动启用该插件
curl -X POST http://127.0.0.1:8317/v8/management/plugins/store/<plugin-id>/install \
  -H "Authorization: Bearer $MANAGEMENT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"version":"1.2.3"}'
```

`version` 可省略以装最新。ID 冲突时加 `?source=<source-id>`。

返回：

```json
{
  "status": "installed",
  "source_id": "official",
  "id": "example-plugin",
  "version": "1.2.3",
  "path": "/abs/path/plugins/example-plugin.so",
  "restart_required": false
}
```

安装流程会：下载 release 资产、校验 checksums、**定向卸载目标插件**、写入新文件、触发配置热重载。

平台或文件锁导致已加载动态库无法覆盖时，返回需要重启的冲突响应（`restart_required: true`）。

安装商店插件会把对应 `plugins.configs.<id>.enabled` 设为 `true`，但**不会**强行打开全局 `plugins.enabled`。

## 发布检查清单

- [ ] 每个目标平台都有对应的 zip
- [ ] zip 根目录直接含动态库，没有多余层级
- [ ] `checksums.txt` 覆盖全部 zip，格式为 sha256 加两个空格
- [ ] release tag 与插件元数据里的 `Version` 一致
- [ ] registry 条目里的 `repository` 是 `https://github.com/{owner}/{repo}` 形式
- [ ] 插件元数据的 `GitHubRepository` 与 registry 的 `repository` 指向同一个仓库
- [ ] 插件 ID 与动态库文件名一致
- [ ] 商店来源可信后再启用（商店可以下载可执行产物）

## 不通过商店分发

也可以只把动态库放到 `plugins/` 目录并手工写配置。这种方式没有 checksums 校验，也没有版本管理，适合本地开发，不适合分发给他人。
