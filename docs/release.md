# 发布与签名

`Lime Pet` 是独立的 desktop companion 应用产物。当前仓库同时维护 macOS 壳与 Windows 壳；发布时它们与 `Lime.app` 分开构建、分开签名、分开分发。

## 当前工作流

仓库已包含两条 GitHub Actions：

- `ci.yml`
  - 对应日常质量校验
  - 在 `pull_request`、`push main`、`workflow_dispatch` 触发
  - macOS 侧统一走 `Swift Package Manager + scripts/build-app.sh`
  - Windows 侧统一走 `WindowsPet/` 下的 `Tauri v2` 构建链路
  - 会验证 macOS debug `.app` 可构建
  - 会验证 Windows companion 可打出 NSIS installer preview
  - 会上传 macOS preview zip 与 Windows preview installer
- `release.yml`
  - 用于 tag / `workflow_dispatch`
  - macOS 侧统一走 `scripts/package-release.sh`
  - Windows 侧统一走 `WindowsPet npm run tauri build`
  - 默认产出 macOS unsigned zip / `sha256` 与 Windows NSIS installer
  - tag 触发时会自动发布到 GitHub Release

## 本地发布命令

```bash
./scripts/package-release.sh --version "0.2.0" --build-number "1"
```

默认产物：

```text
dist/release/LimePet-v0.2.0-macos-unsigned.zip
dist/release/LimePet-v0.2.0-macos-unsigned.zip.sha256
```

Windows 本地产物命令：

```bash
cd WindowsPet
npm install
npm run tauri build
```

典型产物位置：

```text
WindowsPet/src-tauri/target/release/bundle/nsis/*.exe
```

## 版本来源

- App bundle 的 `CFBundleShortVersionString` 由 `--version` 注入
- App bundle 的 `CFBundleVersion` 由 `--build-number` 注入
- `release.yml` 默认使用 GitHub tag 去推导版本号，并用 `github.run_number` 作为构建号
- Windows installer 当前跟随 `WindowsPet/package.json` / `WindowsPet/src-tauri/Cargo.toml` 的仓库版本演进

## Apple 侧材料

若要做正式 macOS 分发，建议准备：

- `Developer ID Application` 证书
- Apple Team ID
- Apple ID / app-specific password

它们可以与 `Lime` 主应用共用同一个 Apple Developer Team，不要求单独购买第二套证书，但 `Lime Pet.app` 仍然必须单独签名和单独 notarize。

## 可扩展的 CI Secret

可按需在仓库里增加：

- `APPLE_TEAM_ID`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_DEVELOPER_ID_CERT_BASE64`
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

当前仓库先不强制启用这些 secret，保证 v1 能先稳定打 unsigned 包。

## 与 Lime 主仓的关系

这里参考了 `lime` 主仓的发布思路，但按 `lime-pet` 当前阶段做了收敛：

- 保留 `Quality` / `Release` 两条主线，而不是把开发构建、发布构建、签名构建拆成多套
- 当前不强制 Apple 签名 secrets，先保证 tag 即可稳定产出 unsigned 下载包
- 当前已经覆盖 macOS 与 Windows 两个 companion 壳，但仍保持最小必要矩阵，不额外引入伪跨平台壳层抽象
