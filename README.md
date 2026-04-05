# Lime Pet

`Lime Pet` 是 `Lime` 的独立桌面 companion app 仓库。当前仓库包含 macOS 原生 `SwiftUI + AppKit` 壳，以及 Windows `Tauri + WebView` companion 壳；它负责桌面端的桌宠呈现、移动、点击和轻提示，不承载 Lime 的主会话运行时。

## 当前能力

- 原生 `SwiftUI + AppKit` 桌宠窗口
- 更完整的桌宠角色表现：呼吸、眨眼、眼神跟随、嘴型、胡须、尾巴摆动、思考态 / 完成态氛围反馈
- 角色资源化：通过 `Resources/character-library.json` 描述多角色主题、配色、几何参数与符号资源
- 角色性格资源化：每个角色都可以定义自己的移动节奏、巡航范围、眨眼频率与陪伴文案
- 角色配件槽位资源化：围脖 / 蝴蝶结 / 项圈、头饰、移动尾迹、脸部标记都由角色配置驱动
- 角色渲染后端资源化：同一套角色库里可以同时声明 `sprite` 与 `live2d` 角色
- 菜单栏支持多角色切换，并持久记住上次选中的外观
- 支持更像桌宠的自主节奏：中央巡航、边缘蹲守、短暂停步、撞边回弹
- 支持拖拽重定位，松手后会记住停靠位置，下次启动自动回到上次区域
- 本地 `WebSocket` companion 协议客户端
- 点击桌宠后向 Lime 发送 `pet.clicked` / `pet.open_chat`
- 单击 / 双击 / 三击支持不同动作：单击唤起 Lime，双击生成一句青柠鼓励，三击生成一句“下一步建议”
- 支持从桌宠右键或状态栏菜单直接输入一句话，请求 Lime 宿主侧模型生成回复，并在桌宠本地朗读
- 断线时会给出提示气泡并自动重连
- 空闲时会有轻量陪伴气泡，不打断主流程
- 菜单栏支持重连、回到屏幕中央、左/中/右停靠、显示 / 隐藏桌宠
- macOS 菜单栏与桌宠右键菜单、Windows 桌宠右键菜单都可直接查看 Companion 连接诊断、最近同步时间与脱敏服务商摘要，并可主动请求 Lime 立即重发摘要
- 新增 `Live2D` 渲染通路：Windows 通过 `Tauri/WebView`，macOS 通过 `WKWebView` 复用同一套本地 runtime
- 默认仅内置青柠；其他 `Live2D` 角色改为服务端模型目录 + 客户端本地安装
- 支持 `Live2D` 模型目录、状态动作映射、点按动作映射，以及 `pet.live2d_action` 协议事件
- 接收 Lime 发来的 `pet.show` / `pet.hide` / `pet.state_changed` / `pet.show_bubble`
- GitHub Actions 质量校验与 tag 发布流程
- Windows companion 预览壳：透明无边框、始终置顶、可拖拽、点击唤起、右键菜单、位置记忆与基础氛围动画

## 仓库结构

- `LimePet.xcodeproj`：Xcode 工程
- `LimePet/`：Swift 源码、`Info.plist` 与 `Resources/` 资源目录
- `WindowsPet/`：Windows companion 子项目，基于 `Tauri v2`
- `LICENSE-Live2D.md`：Live2D 示例模型相关许可说明
- `docs/protocol.md`：Companion 协议说明
- `docs/release.md`：CI/CD 与签名说明
- `.github/workflows/`：构建与打包工作流

## 本地构建

```bash
xcodebuild \
  -project "LimePet.xcodeproj" \
  -target "LimePet" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -derivedDataPath "/tmp/LimePet-DerivedData" \
  build
```

也可以直接用 Xcode 打开 `LimePet.xcodeproj`。如果要做签名运行，请在 Xcode 里给 target 配置自己的 Team。

## 无 Xcode 本地开发

如果当前机器只有 Command Line Tools，没有完整 `Xcode.app`，也可以走仓库内置的本地链路：

```bash
swift build --configuration debug
./scripts/run-dev-app.sh
```

如果只想先产出一个本地调试 `.app` 包：

```bash
./scripts/build-dev-app.sh
open "dist/Lime Pet.app"
```

这条链路基于 `Swift Package Manager` 构建可执行文件，再由脚本封装成 `.app`。它适合本地开发、调试和快速验证；当前仓库的 GitHub Actions 也已经统一走这条路径，避免本地与 CI 使用两套不同构建主线。

如果你正在联调 `lime` 主宿主与桌宠语音链路，也可以直接跑：

```bash
./scripts/run-companion-dev-stack.sh
```

这条脚本会：

- 用 `local-whisper` 特性构建 `lime` 宿主
- 自动重启本地 `lime` companion 监听进程
- 重新启动 `LimePet`
- 默认把桌宠模型目录指向 `http://127.0.0.1:8080` 的 `control-plane-svc`

默认会从 `../aiclientproxy/lime` 查找主仓；如果你的主仓不在这个位置，可以先指定：

```bash
LIME_ROOT="/absolute/path/to/lime" ./scripts/run-companion-dev-stack.sh
```

如果你只是想快速确认当前联调栈是否健康，可以跑：

```bash
./scripts/check-companion-dev-stack.sh
```

它会检查：

- `DevBridge` 是否在线
- 当前默认 ASR 凭证是否存在
- 桌宠是否连上 `45554`
- 如果本地有 `STT` 测试样本，还会顺手打一遍本地 Whisper 转写

## 发布产物

本地生成 release bundle：

```bash
./scripts/package-release.sh --version "0.3.5" --build-number "1"
```

产物默认会按当前宿主架构输出，例如 Apple Silicon 机器上会得到：

```text
dist/release/LimePet-v0.3.5-macos-arm64.dmg
dist/release/LimePet-v0.3.5-macos-arm64.dmg.sha256
dist/release/LimePet-v0.3.5-macos-arm64-unsigned.zip
dist/release/LimePet-v0.3.5-macos-arm64-unsigned.zip.sha256
```

GitHub Actions 发布策略：

- `ci.yml`
  - 在 `pull_request`、`push main`、`workflow_dispatch` 时执行
  - 校验 macOS Apple Silicon 与 macOS Intel 两条构建链都能产出 `.app` 与 release preview
  - 校验 Windows companion 可打出 installer preview
  - 额外上传 `macos-arm64`、`macos-x64` 与 Windows NSIS preview，确保发布链路不腐坏
- `release.yml`
  - 在推送 `v*` tag 时自动执行
  - 也支持手动 `workflow_dispatch`
  - 会同时上传 `macos-arm64`、`macos-x64` 两个 macOS dmg、unsigned zip、对应 `sha256` 与 Windows NSIS installer，并发布到 GitHub Release

## Windows 本地开发

Windows 壳位于 `WindowsPet/`，它复用同一套 companion 协议和共享素材，但不复用 macOS 的窗口层代码。

常用命令：

```bash
cd WindowsPet
npm install
npm run build
```

如果在 Windows 机器上做本地桌宠调试：

```bash
cd WindowsPet
npm install
npm run tauri dev
```

如果在 Windows 机器上产出 installer：

```bash
cd WindowsPet
npm install
npm run tauri build
```

## Companion 连接

默认连接地址：

```text
ws://127.0.0.1:45554/companion/pet
```

也支持通过启动参数覆盖：

```bash
open -a "Lime Pet.app" --args \
  --connect "ws://127.0.0.1:45554/companion/pet" \
  --control-plane-base-url "http://127.0.0.1:8080" \
  --tenant-id "tenant-0001" \
  --client-id "lime" \
  --protocol-version "1"
```

详细消息格式见 [docs/protocol.md](docs/protocol.md)。

## 模型安装

当前桌宠的事实源已经拆成两层：

- 内置角色：`LimePet/Resources/character-library.json`，当前默认只保留青柠
- 可安装角色：`LimePet/Resources/live2d-model-catalog.json`，同时会生成到 `limecore` 的 seed 文件

macOS 客户端会优先尝试从：

```text
GET http://127.0.0.1:8080/api/v1/public/tenants/tenant-0001/client/model-catalog
```

拉取公开模型目录；拿不到时会回退到 bundle 内置的 catalog。模型文件实际安装到：

```text
~/Library/Application Support/LimePet/live2d-models
```

安装记录保存在：

```text
~/Library/Application Support/LimePet/model-installs.json
```

角色外观与动作配置仍然优先沿用 JSON 描述 + Swift 渲染器 / Live2D runtime 的组合，而不是把外观和节奏写死在视图里。

如果要本地启动 `control-plane-svc` 做联调，可以在 `limecore` 仓库执行：

```bash
cd ~/Documents/dev/ai/limecloud/limecore
SERVER_MODEL_ASSET_ROOT_DIR="/absolute/path/to/live2d-models/models" \
go run ./services/control-plane-svc/cmd/server
```

推荐把你本地克隆的 `live2d-models/models` 目录挂进 `control-plane-svc`。这样公开模型目录返回的下载地址会指向当前本地服务，例如：

```text
http://127.0.0.1:8080/api/v1/public/assets/live2d/koharu/model.json
```

这条链路可以避开 `model.oml2d.com` 证书或 TLS 握手异常导致的安装失败。

如果准备把模型正式迁到 Cloudflare 托管，不再依赖本地目录或 `model.oml2d.com`，统一在 `limecore` 仓库执行批量导入：

```bash
cd ~/Documents/dev/ai/limecloud/limecore
npm run import:cloudflare:live2d -- \
  --source-dir "/absolute/path/to/live2d-models" \
  --bucket "<your-r2-bucket>" \
  --asset-base-url "https://<your-asset-domain>"
```

这条命令会整批上传模型目录，并同步改写 `lime-pet` / `limecore` 的模型目录 seed，不需要后台逐个上传。

## 跨平台策略

当前仓库采用“同仓双壳”的做法：

- macOS：保留原生 `SwiftUI + AppKit`
- Windows：新增 `Tauri + WebView` 壳
- 协议：两侧统一复用 `docs/protocol.md` 定义的 companion WebSocket 协议
- 资源：Windows 壳通过同步脚本复用主仓的青柠精灵素材，而不是维护第二份角色源图
