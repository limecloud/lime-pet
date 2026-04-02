# Lime Companion Protocol v1

本协议用于 `Lime` 主应用与 `Lime Pet` 之间的本地双向通信。

## 连接方式

- 传输：`WebSocket`
- 默认地址：`ws://127.0.0.1:45554/companion/pet`
- 范围：仅本机回环地址

## 消息包格式

所有消息统一使用：

```json
{
  "protocol_version": 1,
  "event": "pet.state_changed",
  "payload": {}
}
```

字段约束：

- `protocol_version`：当前固定为 `1`
- `event`：事件名
- `payload`：事件负载

## Lime -> Pet

### `pet.show`

```json
{
  "protocol_version": 1,
  "event": "pet.show",
  "payload": {}
}
```

### `pet.hide`

```json
{
  "protocol_version": 1,
  "event": "pet.hide",
  "payload": {}
}
```

### `pet.state_changed`

```json
{
  "protocol_version": 1,
  "event": "pet.state_changed",
  "payload": {
    "state": "thinking"
  }
}
```

允许状态：

- `hidden`
- `idle`
- `walking`
- `thinking`
- `done`

### `pet.show_bubble`

```json
{
  "protocol_version": 1,
  "event": "pet.show_bubble",
  "payload": {
    "text": "Lime 正在整理结果…",
    "auto_hide_ms": 1800
  }
}
```

### `pet.open_chat_anchor`

```json
{
  "protocol_version": 1,
  "event": "pet.open_chat_anchor",
  "payload": {}
}
```

### `pet.provider_overview`

桌宠只接收脱敏后的 provider 摘要，不直接读取 Lime 的原始凭证。

```json
{
  "protocol_version": 1,
  "event": "pet.provider_overview",
  "payload": {
    "providers": [
      {
        "provider_type": "openai",
        "display_name": "OpenAI",
        "total_count": 2,
        "healthy_count": 1,
        "available": true,
        "needs_attention": true
      }
    ],
    "total_provider_count": 1,
    "available_provider_count": 1,
    "needs_attention_provider_count": 1
  }
}
```

本事件会被 companion 壳转换成本地诊断视图，例如连接状态、最近同步时间、建议动作和前几项服务商摘要；这些诊断都来源于脱敏 payload，不会反查原始凭证。

## Pet -> Lime

### `pet.ready`

```json
{
  "protocol_version": 1,
  "event": "pet.ready",
  "payload": {
    "client_id": "lime",
    "platform": "windows",
    "capabilities": [
      "bubble",
      "movement",
      "tap-open-chat",
      "drag-reposition",
      "reactive-animations",
      "perch-memory",
      "ambient-dialogue",
      "character-themes",
      "provider-overview",
      "provider-sync-request",
      "open-provider-settings",
      "multi-tap-actions"
    ]
  }
}
```

### `pet.clicked`

```json
{
  "protocol_version": 1,
  "event": "pet.clicked",
  "payload": {
    "source": "pet"
  }
}
```

### `pet.open_chat`

```json
{
  "protocol_version": 1,
  "event": "pet.open_chat",
  "payload": {
    "source": "pet"
  }
}
```

### `pet.dismissed`

```json
{
  "protocol_version": 1,
  "event": "pet.dismissed",
  "payload": {
    "source": "pet"
  }
}
```

### `pet.open_provider_settings`

```json
{
  "protocol_version": 1,
  "event": "pet.open_provider_settings",
  "payload": {
    "source": "context_menu"
  }
}
```

### `pet.request_provider_overview_sync`

桌宠请求 Lime 立即重发一次最新的脱敏 provider 摘要。该事件不要求主窗口前置，也不允许桌宠直接读取真实凭证。

```json
{
  "protocol_version": 1,
  "event": "pet.request_provider_overview_sync",
  "payload": {
    "source": "context_menu"
  }
}
```

### `pet.request_pet_cheer`

桌宠双击后可请求 Lime 复用当前可聊天的 AI 服务商，生成一句短鼓励或陪伴气泡。

```json
{
  "protocol_version": 1,
  "event": "pet.request_pet_cheer",
  "payload": {
    "source": "double_tap"
  }
}
```

### `pet.request_pet_next_step`

桌宠三击后可请求 Lime 复用当前可聊天的 AI 服务商，生成一句简短的“下一步建议”气泡。

```json
{
  "protocol_version": 1,
  "event": "pet.request_pet_next_step",
  "payload": {
    "source": "triple_tap"
  }
}
```

### `pet.ready` capability 说明

- `platform`：当前实现值可以是 `macos` 或 `windows`
- `capabilities`：允许按具体 companion 壳裁剪，不要求每个平台完全一致
- macOS 当前会额外声明 `dock-presets`；Windows 当前更偏向窗口自由拖拽与右键诊断面板

- `bubble`：支持提示气泡
- `movement`：支持自主移动
- `tap-open-chat`：支持点击后拉起 Lime
- `multi-tap-actions`：支持双击 / 三击触发不同的桌宠动作
- `drag-reposition`：支持拖拽重新停靠
- `reactive-animations`：支持基于状态的动画反馈
- `perch-memory`：支持记忆上次停靠位置
- `dock-presets`：支持左 / 中 / 右停靠预设
- `ambient-dialogue`：支持空闲陪伴气泡
- `character-themes`：支持资源化角色主题、本地切换，以及角色级动作 / 文案 / 配件槽位配置
- `provider-overview`：支持接收 Lime 下发的脱敏 provider 摘要
- `provider-sync-request`：支持桌宠主动请求 Lime 立即重发一次最新的脱敏 provider 摘要
- `open-provider-settings`：支持从桌宠回跳 Lime 的 AI 服务商设置页

## 兼容策略

- 主版本只认 `protocol_version = 1`
- 版本不匹配时允许忽略消息，并在本地日志中记录
- v1 不做复杂协商；若升级协议，优先升级主应用与 companion
