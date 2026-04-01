import { invoke } from "@tauri-apps/api/core";
import { currentMonitor, getCurrentWindow, PhysicalPosition } from "@tauri-apps/api/window";
import "./styles.css";

type PetState = "hidden" | "idle" | "walking" | "thinking" | "done";

type IncomingEvent =
  | "pet.show"
  | "pet.hide"
  | "pet.state_changed"
  | "pet.show_bubble"
  | "pet.open_chat_anchor";

interface LaunchConfig {
  endpoint: string | null;
  client_id: string;
  protocol_version: number;
}

interface InboundEnvelope {
  protocol_version: number;
  event: IncomingEvent | string;
  payload?: Record<string, unknown>;
}

interface OutboundEnvelope<TPayload> {
  protocol_version: number;
  event: string;
  payload: TPayload;
}

interface WindowPositionSnapshot {
  x: number;
  y: number;
}

const windowPositionKey = "lime-pet.windows.position.v1";
const reconnectDelayMs = 5000;
const dragThreshold = 6;
const appWindow = getCurrentWindow();

function requiredElement<TElement extends Element>(selector: string): TElement {
  const element = document.querySelector<TElement>(selector);
  if (!element) {
    throw new Error(`Lime Pet Windows UI 初始化失败: ${selector}`);
  }
  return element;
}

const shell = requiredElement<HTMLElement>("#app");
const petButton = requiredElement<HTMLButtonElement>("#petButton");
const bubble = requiredElement<HTMLElement>("#bubble");
const connectionLabel = requiredElement<HTMLElement>("#connectionLabel");
const modeLabel = requiredElement<HTMLElement>("#modeLabel");
const contextMenu = requiredElement<HTMLElement>("#contextMenu");

const ambientLines = {
  connected: {
    idle: ["我在 Windows 桌面待命", "这里也能陪着你守着 Lime"],
    walking: ["我在这边轻轻巡航", "Windows 这侧也交给我盯着"],
    thinking: ["Lime 正在思考，我先安静陪着", "有进展我会先冒个泡"],
    done: ["刚刚那件事完成啦", "Windows 侧也收到完成气泡了"]
  },
  disconnected: {
    idle: ["我还在等 Lime 连上来", "连上以后我就能同步动起来"],
    walking: ["现在先在这里守着", "离线时我也会留在这里"],
    thinking: ["主应用还没连上，我先等等", "连接恢复后我会继续同步状态"],
    done: ["等 Lime 连上来，我再继续庆祝", "先别急，我还在等连接恢复"]
  }
} as const;

const state = {
  config: null as LaunchConfig | null,
  socket: null as WebSocket | null,
  connected: false,
  petState: "walking" as PetState,
  bubbleText: "",
  dragging: false,
  reconnectTimer: null as number | null,
  bubbleTimer: null as number | null,
  ambientTimer: null as number | null,
  dragCandidate: null as { x: number; y: number; moved: boolean } | null
};

function updateShellClasses(): void {
  shell.className = [
    "pet-shell",
    `state-${state.petState}`,
    state.connected ? "connected" : "disconnected",
    state.dragging ? "dragging" : ""
  ]
    .filter(Boolean)
    .join(" ");
}

function modeLabelFor(currentState: PetState): string {
  switch (currentState) {
    case "hidden":
      return "已隐藏";
    case "idle":
      return state.connected ? "静静陪伴" : "等待连接";
    case "walking":
      return state.connected ? "中央巡航" : "离线守候";
    case "thinking":
      return "同步思考";
    case "done":
      return "完成庆祝";
  }
}

function renderLabels(): void {
  connectionLabel.textContent = state.connected ? "已连接" : "等待连接";
  modeLabel.textContent = modeLabelFor(state.petState);
}

function renderBubble(): void {
  bubble.textContent = state.bubbleText;
  bubble.classList.toggle("visible", state.bubbleText.length > 0);
}

function render(): void {
  updateShellClasses();
  renderLabels();
  renderBubble();
}

function clearBubbleTimer(): void {
  if (state.bubbleTimer !== null) {
    window.clearTimeout(state.bubbleTimer);
    state.bubbleTimer = null;
  }
}

function showBubble(text: string, autoHideMs = 1600): void {
  state.bubbleText = text;
  clearBubbleTimer();
  renderBubble();

  if (autoHideMs > 0) {
    state.bubbleTimer = window.setTimeout(() => {
      state.bubbleText = "";
      renderBubble();
      state.bubbleTimer = null;
    }, autoHideMs);
  }
}

function hideBubble(): void {
  clearBubbleTimer();
  state.bubbleText = "";
  renderBubble();
}

function setPetState(nextState: PetState): void {
  state.petState = nextState;
  render();
}

function closeContextMenu(): void {
  contextMenu.classList.add("hidden");
}

function openContextMenu(x: number, y: number): void {
  contextMenu.style.left = `${x}px`;
  contextMenu.style.top = `${y}px`;
  contextMenu.classList.remove("hidden");
}

function saveWindowPosition(position: WindowPositionSnapshot): void {
  localStorage.setItem(windowPositionKey, JSON.stringify(position));
}

async function centerWindowOnCurrentMonitor(): Promise<void> {
  const monitor = await currentMonitor();
  const monitorPosition = monitor?.position ?? { x: 0, y: 0 };
  const monitorSize = monitor?.size ?? { width: 1440, height: 900 };

  const windowWidth = 280;
  const windowHeight = 300;
  const x = monitorPosition.x + Math.round((monitorSize.width - windowWidth) / 2);
  const y = monitorPosition.y + monitorSize.height - windowHeight - 88;

  await appWindow.setPosition(new PhysicalPosition(x, y));
}

async function restoreWindowPosition(): Promise<void> {
  const raw = localStorage.getItem(windowPositionKey);
  if (!raw) {
    await centerWindowOnCurrentMonitor();
    return;
  }

  try {
    const parsed = JSON.parse(raw) as WindowPositionSnapshot;
    if (typeof parsed.x === "number" && typeof parsed.y === "number") {
      await appWindow.setPosition(new PhysicalPosition(parsed.x, parsed.y));
      return;
    }
  } catch {
    // ignore and recenter below
  }

  await centerWindowOnCurrentMonitor();
}

function clearReconnectTimer(): void {
  if (state.reconnectTimer !== null) {
    window.clearTimeout(state.reconnectTimer);
    state.reconnectTimer = null;
  }
}

function scheduleReconnect(reason: string): void {
  clearReconnectTimer();
  showBubble(reason, 1500);
  state.reconnectTimer = window.setTimeout(() => {
    state.reconnectTimer = null;
    void connectSocket();
  }, reconnectDelayMs);
}

function sendEnvelope<TPayload>(event: string, payload: TPayload): void {
  if (!state.socket || state.socket.readyState !== WebSocket.OPEN || !state.config) {
    return;
  }

  const envelope: OutboundEnvelope<TPayload> = {
    protocol_version: state.config.protocol_version,
    event,
    payload
  };

  state.socket.send(JSON.stringify(envelope));
}

function sendReadyEvent(): void {
  if (!state.config) {
    return;
  }

  sendEnvelope("pet.ready", {
    client_id: state.config.client_id,
    platform: "windows",
    capabilities: [
      "bubble",
      "movement",
      "tap-open-chat",
      "drag-reposition",
      "reactive-animations",
      "perch-memory",
      "ambient-dialogue",
      "character-themes"
    ]
  });
}

function sendTapEvents(): void {
  sendEnvelope("pet.clicked", { source: "pet" });
  sendEnvelope("pet.open_chat", { source: "pet" });
}

function sendDismissed(source: string): void {
  sendEnvelope("pet.dismissed", { source });
}

function randomAmbientLine(): string | null {
  const lineSet = state.connected ? ambientLines.connected : ambientLines.disconnected;
  const lines = lineSet[state.petState === "hidden" ? "idle" : state.petState];
  if (!lines.length) {
    return null;
  }
  return lines[Math.floor(Math.random() * lines.length)] ?? null;
}

function restartAmbientLoop(): void {
  if (state.ambientTimer !== null) {
    window.clearInterval(state.ambientTimer);
  }

  state.ambientTimer = window.setInterval(() => {
    if (state.petState === "hidden" || state.dragging || state.bubbleText) {
      return;
    }

    const line = randomAmbientLine();
    if (line) {
      showBubble(line, 1500);
    }
  }, 14000);
}

async function handleIncomingMessage(rawText: string): Promise<void> {
  let envelope: InboundEnvelope;

  try {
    envelope = JSON.parse(rawText) as InboundEnvelope;
  } catch {
    return;
  }

  if (!state.config || envelope.protocol_version !== state.config.protocol_version) {
    showBubble(`协议版本不兼容：${String(envelope.protocol_version)}`, 1800);
    return;
  }

  switch (envelope.event) {
    case "pet.show":
      await appWindow.show();
      if (state.petState === "hidden") {
        setPetState("walking");
      }
      break;
    case "pet.hide":
      setPetState("hidden");
      await appWindow.hide();
      break;
    case "pet.state_changed": {
      const nextState = envelope.payload?.state;
      if (nextState === "hidden" || nextState === "idle" || nextState === "walking" || nextState === "thinking" || nextState === "done") {
        setPetState(nextState);
      }
      break;
    }
    case "pet.show_bubble": {
      const text = envelope.payload?.text;
      const autoHideMs = envelope.payload?.auto_hide_ms;
      if (typeof text === "string") {
        showBubble(text, typeof autoHideMs === "number" ? autoHideMs : 1800);
      }
      break;
    }
    case "pet.open_chat_anchor":
      showBubble("点我打开 Lime 对话", 1600);
      break;
    default:
      break;
  }
}

async function connectSocket(): Promise<void> {
  if (!state.config?.endpoint) {
    showBubble("未配置 Lime Companion 地址", 1800);
    return;
  }

  if (state.socket && state.socket.readyState === WebSocket.OPEN) {
    return;
  }

  clearReconnectTimer();

  const socket = new WebSocket(state.config.endpoint);
  state.socket = socket;

  socket.addEventListener("open", () => {
    state.connected = true;
    render();
    sendReadyEvent();
    showBubble("已连接到 Lime", 1200);
  });

  socket.addEventListener("message", (event) => {
    if (typeof event.data === "string") {
      void handleIncomingMessage(event.data);
    }
  });

  socket.addEventListener("close", () => {
    if (state.socket !== socket) {
      return;
    }

    state.connected = false;
    state.socket = null;
    render();
    scheduleReconnect("Windows 桌宠连接已断开，稍后重试");
  });

  socket.addEventListener("error", () => {
    socket.close();
  });
}

async function handlePetTap(): Promise<void> {
  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("正在唤起 Lime…", 1200);
  sendTapEvents();
}

async function hidePetFromMenu(): Promise<void> {
  sendDismissed("menu");
  setPetState("hidden");
  await appWindow.hide();
}

async function quitApp(): Promise<void> {
  closeContextMenu();
  await appWindow.close();
}

function bindContextMenuActions(): void {
  contextMenu.addEventListener("click", (event) => {
    const target = event.target as HTMLElement | null;
    const action = target?.dataset.action;

    if (!action) {
      return;
    }

    closeContextMenu();

    switch (action) {
      case "recenter":
        void centerWindowOnCurrentMonitor().then(() => showBubble("回到屏幕中央啦", 1200));
        break;
      case "hide":
        void hidePetFromMenu();
        break;
      case "quit":
        void quitApp();
        break;
      default:
        break;
    }
  });
}

function bindWindowGestures(): void {
  petButton.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) {
      return;
    }

    closeContextMenu();
    state.dragCandidate = {
      x: event.screenX,
      y: event.screenY,
      moved: false
    };
  });

  petButton.addEventListener("pointermove", (event) => {
    if (!state.dragCandidate || state.dragCandidate.moved) {
      return;
    }

    const distance = Math.hypot(event.screenX - state.dragCandidate.x, event.screenY - state.dragCandidate.y);
    if (distance < dragThreshold) {
      return;
    }

    state.dragCandidate.moved = true;
    state.dragging = true;
    render();
    showBubble("把我拖到喜欢的位置", 900);

    void appWindow.startDragging().finally(() => {
      state.dragging = false;
      render();
    });
  });

  petButton.addEventListener("pointerup", () => {
    if (!state.dragCandidate) {
      return;
    }

    const shouldTap = !state.dragCandidate.moved;
    state.dragCandidate = null;

    if (shouldTap) {
      void handlePetTap();
    }
  });

  petButton.addEventListener("contextmenu", (event) => {
    event.preventDefault();
    openContextMenu(event.clientX + 8, event.clientY - 6);
  });

  document.addEventListener("click", (event) => {
    if (!contextMenu.contains(event.target as Node)) {
      closeContextMenu();
    }
  });

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeContextMenu();
      hideBubble();
    }
  });
}

async function initializeWindowBehavior(): Promise<void> {
  await appWindow.setAlwaysOnTop(true);
  await restoreWindowPosition();

  await appWindow.onMoved(({ payload }) => {
    saveWindowPosition({
      x: payload.x,
      y: payload.y
    });
  });
}

async function bootstrap(): Promise<void> {
  state.config = await invoke<LaunchConfig>("load_launch_config");
  render();
  bindContextMenuActions();
  bindWindowGestures();
  restartAmbientLoop();
  await initializeWindowBehavior();
  await connectSocket();
  showBubble("拖拽我换个位置，轻点我打开 Lime", 1800);
}

void bootstrap();
