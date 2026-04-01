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

## Pet -> Lime

### `pet.ready`

```json
{
  "protocol_version": 1,
  "event": "pet.ready",
  "payload": {
    "client_id": "lime",
    "platform": "macos",
    "capabilities": [
      "bubble",
      "movement",
      "tap-open-chat",
      "drag-reposition",
      "reactive-animations",
      "perch-memory",
      "dock-presets",
      "ambient-dialogue",
      "character-themes"
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

### `pet.ready` capability 说明

- `bubble`：支持提示气泡
- `movement`：支持自主移动
- `tap-open-chat`：支持点击后拉起 Lime
- `drag-reposition`：支持拖拽重新停靠
- `reactive-animations`：支持基于状态的动画反馈
- `perch-memory`：支持记忆上次停靠位置
- `dock-presets`：支持左 / 中 / 右停靠预设
- `ambient-dialogue`：支持空闲陪伴气泡
- `character-themes`：支持资源化角色主题、本地切换，以及角色级动作 / 文案 / 配件槽位配置

## 兼容策略

- 主版本只认 `protocol_version = 1`
- 版本不匹配时允许忽略消息，并在本地日志中记录
- v1 不做复杂协商；若升级协议，优先升级主应用与 companion
