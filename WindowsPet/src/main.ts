import { invoke } from "@tauri-apps/api/core";
import { currentMonitor, getCurrentWindow, PhysicalPosition } from "@tauri-apps/api/window";
import {
  defaultCompanionEndpoint,
  makeCompanionDiagnosticSnapshot,
  petCompanionCapabilities,
  providerOverviewBubbleText,
  providerOverviewFingerprint,
  type CompanionDiagnosticSnapshot,
  type ProviderOverviewItem,
  type ProviderOverviewPayload
} from "./companionDiagnostics";
import "./styles.css";

type PetState = "hidden" | "idle" | "walking" | "thinking" | "done";

type IncomingEvent =
  | "pet.show"
  | "pet.hide"
  | "pet.state_changed"
  | "pet.show_bubble"
  | "pet.open_chat_anchor"
  | "pet.provider_overview";

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
const diagnosticSummary = requiredElement<HTMLElement>("#diagnosticSummary");
const diagnosticChecklist = requiredElement<HTMLElement>("#diagnosticChecklist");
const providerOverviewList = requiredElement<HTMLElement>("#providerOverviewList");

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
  tapTimer: null as number | null,
  tapCount: 0,
  dragCandidate: null as { x: number; y: number; moved: boolean } | null,
  providerOverviewFingerprint: null as string | null,
  latestProviderOverview: null as ProviderOverviewPayload | null,
  lastProviderOverviewAt: null as number | null,
  lastConnectionReason: null as string | null,
  endpointLabel: defaultCompanionEndpoint,
  hasConnectedOnce: false,
  companionDiagnostic: makeCompanionDiagnosticSnapshot({
    endpointLabel: defaultCompanionEndpoint,
    endpointConfigured: true,
    isConnected: false,
    lastConnectionReason: null,
    hasConnectedOnce: false,
    latestProviderOverview: null,
    lastProviderOverviewAt: null
  }) as CompanionDiagnosticSnapshot
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

function refreshCompanionDiagnosticSnapshot(): void {
  state.companionDiagnostic = makeCompanionDiagnosticSnapshot({
    endpointLabel: state.endpointLabel,
    endpointConfigured: state.endpointLabel !== "未配置",
    isConnected: state.connected,
    lastConnectionReason: state.lastConnectionReason,
    hasConnectedOnce: state.hasConnectedOnce,
    latestProviderOverview: state.latestProviderOverview,
    lastProviderOverviewAt: state.lastProviderOverviewAt
  });
}

function renderReadonlyLines(container: HTMLElement, lines: string[]): void {
  container.replaceChildren(
    ...lines.map((line) => {
      const item = document.createElement("div");
      item.className = "context-static-item";
      item.textContent = line;
      return item;
    }),
  );
}

function renderCompanionDiagnostics(): void {
  refreshCompanionDiagnosticSnapshot();

  renderReadonlyLines(diagnosticSummary, [
    state.companionDiagnostic.connectionLine,
    state.companionDiagnostic.endpointLine,
    state.companionDiagnostic.syncLine,
    state.companionDiagnostic.lastSyncLine,
    state.companionDiagnostic.actionLine
  ]);
  renderReadonlyLines(diagnosticChecklist, state.companionDiagnostic.checkLines);
  renderReadonlyLines(providerOverviewList, state.companionDiagnostic.providerLines);
}

function render(): void {
  updateShellClasses();
  renderLabels();
  renderBubble();
  renderCompanionDiagnostics();
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
  contextMenu.classList.remove("hidden");

  const margin = 8;
  const maxX = window.innerWidth - contextMenu.offsetWidth - margin;
  const maxY = window.innerHeight - contextMenu.offsetHeight - margin;
  const clampedX = Math.min(Math.max(x, margin), Math.max(margin, maxX));
  const clampedY = Math.min(Math.max(y, margin), Math.max(margin, maxY));

  contextMenu.style.left = `${clampedX}px`;
  contextMenu.style.top = `${clampedY}px`;
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
  state.lastConnectionReason = reason;
  render();
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
    capabilities: petCompanionCapabilities
  });
}

function sendTapEvents(): void {
  sendEnvelope("pet.clicked", { source: "pet" });
  sendEnvelope("pet.open_chat", { source: "pet" });
}

function sendDismissed(source: string): void {
  sendEnvelope("pet.dismissed", { source });
}

function parseProviderOverview(
  payload?: Record<string, unknown>,
): ProviderOverviewPayload | null {
  if (!payload) {
    return null;
  }

  const totalProviderCount = payload.total_provider_count;
  const availableProviderCount = payload.available_provider_count;
  const needsAttentionProviderCount = payload.needs_attention_provider_count;

  if (
    typeof totalProviderCount !== "number" ||
    typeof availableProviderCount !== "number" ||
    typeof needsAttentionProviderCount !== "number"
  ) {
    return null;
  }

  const providers = Array.isArray(payload.providers)
    ? payload.providers
        .map((item) => {
          if (!item || typeof item !== "object") {
            return null;
          }

          const candidate = item as Record<string, unknown>;
          if (
            typeof candidate.provider_type !== "string" ||
            typeof candidate.display_name !== "string" ||
            typeof candidate.total_count !== "number" ||
            typeof candidate.healthy_count !== "number" ||
            typeof candidate.available !== "boolean" ||
            typeof candidate.needs_attention !== "boolean"
          ) {
            return null;
          }

          return {
            provider_type: candidate.provider_type,
            display_name: candidate.display_name,
            total_count: candidate.total_count,
            healthy_count: candidate.healthy_count,
            available: candidate.available,
            needs_attention: candidate.needs_attention
          } satisfies ProviderOverviewItem;
        })
        .filter((item): item is ProviderOverviewItem => item !== null)
    : [];

  return {
    providers,
    total_provider_count: totalProviderCount,
    available_provider_count: availableProviderCount,
    needs_attention_provider_count: needsAttentionProviderCount
  };
}

function announceProviderOverview(payload: ProviderOverviewPayload): void {
  const fingerprint = providerOverviewFingerprint(payload);
  state.latestProviderOverview = payload;
  state.lastProviderOverviewAt = Date.now();
  render();

  if (fingerprint === state.providerOverviewFingerprint) {
    return;
  }

  state.providerOverviewFingerprint = fingerprint;

  const shouldInterruptCurrentBubble =
    payload.total_provider_count === 0 ||
    payload.available_provider_count === 0 ||
    payload.needs_attention_provider_count > 0;

  if (!state.bubbleText || shouldInterruptCurrentBubble) {
    showBubble(
      providerOverviewBubbleText(payload),
      shouldInterruptCurrentBubble ? 2100 : 1500,
    );
  }
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
    case "pet.provider_overview": {
      const overview = parseProviderOverview(envelope.payload);
      if (overview) {
        announceProviderOverview(overview);
      }
      break;
    }
    default:
      break;
  }
}

async function connectSocket(): Promise<void> {
  if (!state.config?.endpoint) {
    state.endpointLabel = "未配置";
    state.lastConnectionReason = "未配置 Lime Companion 地址";
    render();
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
    state.endpointLabel = state.config?.endpoint ?? state.endpointLabel;
    state.lastConnectionReason = null;
    state.hasConnectedOnce = true;
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

function requestPetCheer(source: string): void {
  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("青柠想一句鼓励给你…", 1400);
  sendEnvelope("pet.request_pet_cheer", { source });
}

function requestPetNextStep(source: string): void {
  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("青柠在想你的下一步…", 1400);
  sendEnvelope("pet.request_pet_next_step", { source });
}

function dispatchTapAction(): void {
  const tapCount = state.tapCount;
  state.tapCount = 0;
  if (state.tapTimer !== null) {
    window.clearTimeout(state.tapTimer);
    state.tapTimer = null;
  }

  if (tapCount >= 3) {
    requestPetNextStep("triple_tap");
    return;
  }

  if (tapCount === 2) {
    requestPetCheer("double_tap");
    return;
  }

  void handlePetTap();
}

function registerPetTap(): void {
  state.tapCount = Math.min(state.tapCount + 1, 3);
  if (state.tapTimer !== null) {
    window.clearTimeout(state.tapTimer);
  }
  state.tapTimer = window.setTimeout(() => {
    dispatchTapAction();
  }, 320);
}

async function hidePetFromMenu(): Promise<void> {
  sendDismissed("menu");
  setPetState("hidden");
  await appWindow.hide();
}

function reconnectFromMenu(): void {
  clearReconnectTimer();
  showBubble("正在尝试重新连接 Lime…", 1200);
  void connectSocket();
}

function requestProviderOverviewSync(source: string): void {
  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("正在请求同步桌宠摘要…", 1200);
  sendEnvelope("pet.request_provider_overview_sync", { source });
}

function openProviderSettings(source: string): void {
  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("正在打开 AI 服务商设置…", 1200);
  sendEnvelope("pet.open_provider_settings", { source });
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
      case "reconnect":
        reconnectFromMenu();
        break;
      case "sync-provider-overview":
        requestProviderOverviewSync("context_menu");
        break;
      case "provider-settings":
        openProviderSettings("context_menu");
        break;
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
      registerPetTap();
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
  state.endpointLabel = state.config.endpoint ?? "未配置";
  render();
  bindContextMenuActions();
  bindWindowGestures();
  restartAmbientLoop();
  await initializeWindowBehavior();
  await connectSocket();
  showBubble("轻点打开 Lime，双击听青柠一句话，三击拿下一步建议", 2200);
}

void bootstrap();
