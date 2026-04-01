# Lime Pet

`Lime Pet` 是 `Lime` 的独立 macOS companion app。它负责桌面端的桌宠呈现、移动、点击和轻提示，不承载 Lime 的主会话运行时。

## 当前能力

- 原生 `SwiftUI + AppKit` 桌宠窗口
- 更完整的桌宠角色表现：呼吸、眨眼、眼神跟随、嘴型、胡须、尾巴摆动、思考态 / 完成态氛围反馈
- 角色资源化：通过 `Resources/character-library.json` 描述多角色主题、配色、几何参数与符号资源
- 角色性格资源化：每个角色都可以定义自己的移动节奏、巡航范围、眨眼频率与陪伴文案
- 角色配件槽位资源化：围脖 / 蝴蝶结 / 项圈、头饰、移动尾迹、脸部标记都由角色配置驱动
- 菜单栏支持多角色切换，并持久记住上次选中的外观
- 支持更像桌宠的自主节奏：中央巡航、边缘蹲守、短暂停步、撞边回弹
- 支持拖拽重定位，松手后会记住停靠位置，下次启动自动回到上次区域
- 本地 `WebSocket` companion 协议客户端
- 点击桌宠后向 Lime 发送 `pet.clicked` / `pet.open_chat`
- 断线时会给出提示气泡并自动重连
- 空闲时会有轻量陪伴气泡，不打断主流程
- 菜单栏支持重连、回到屏幕中央、左/中/右停靠、显示 / 隐藏桌宠
- 接收 Lime 发来的 `pet.show` / `pet.hide` / `pet.state_changed` / `pet.show_bubble`
- GitHub Actions 质量校验与 tag 发布流程

## 仓库结构

- `LimePet.xcodeproj`：Xcode 工程
- `LimePet/`：Swift 源码、`Info.plist` 与 `Resources/` 资源目录
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

## 发布产物

本地生成 release zip：

```bash
./scripts/package-release.sh --version "0.1.0" --build-number "1"
```

产物默认输出到：

```text
dist/release/LimePet-v0.1.0-macos-unsigned.zip
dist/release/LimePet-v0.1.0-macos-unsigned.zip.sha256
```

GitHub Actions 发布策略：

- `ci.yml`
  - 在 `pull_request`、`push main`、`workflow_dispatch` 时执行
  - 校验 debug `.app` 可构建
  - 额外打一个 release preview zip，确保发布链路不腐坏
- `release.yml`
  - 在推送 `v*` tag 时自动执行
  - 也支持手动 `workflow_dispatch`
  - 会上传 zip 与 `sha256`，并发布到 GitHub Release

## Companion 连接

默认连接地址：

```text
ws://127.0.0.1:45554/companion/pet
```

也支持通过启动参数覆盖：

```bash
open -a "Lime Pet.app" --args \
  --connect "ws://127.0.0.1:45554/companion/pet" \
  --client-id "lime" \
  --protocol-version "1"
```

详细消息格式见 [docs/protocol.md](docs/protocol.md)。

角色资源库默认从 `LimePet/Resources/character-library.json` 打包进 app bundle；后续如果要扩展更多桌宠皮肤，优先沿用这套 JSON 描述 + Swift 渲染器 + 角色行为参数 + 配件槽位的组合，而不是直接把外观和节奏写死在视图里。

## 未来 Windows 策略

当前仓库只实现 macOS 壳。未来跨 Windows 时，复用同一套 Companion Protocol，在单独的 Windows 壳里实现窗口、动画和命中，不强行复用 macOS 的窗口层代码。当前 CI/CD 只验证 macOS 产物，Windows 发布链路尚未实现。
