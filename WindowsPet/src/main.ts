import {
  characterById,
  characterCatalog,
  characterRenderer,
  defaultCharacter,
  live2dEnvelopeAction,
  live2dStageSize,
  live2dStateAction,
  live2dTapAction,
  type PetCharacterTheme,
  type PetState
} from "./characterLibrary";
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
import { Live2DFrameDriver } from "./live2dBridge";
import {
  appWindow,
  currentMonitorCompat,
  invokeCompat,
  isTauriRuntime,
  toPhysicalPosition
} from "./tauriCompat";
import "./styles.css";

type IncomingEvent =
  | "pet.show"
  | "pet.hide"
  | "pet.state_changed"
  | "pet.show_bubble"
  | "pet.open_chat_anchor"
  | "pet.provider_overview"
  | "pet.live2d_action";

type StatusTone = "info" | "success" | "warning" | "error";
type StatusActionKey = "reconnect" | "retry-live2d";
type DockSide = "left" | "right";

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

interface SystemStatusState {
  title: string;
  message: string;
  tone: StatusTone;
  actionKey: StatusActionKey | null;
}

interface Live2DRuntimeSummary {
  characterId: string;
  modelPath: string;
  format: string;
  motionGroups: string[];
  expressionCount: number;
}

interface Live2DHostEnvelope {
  source?: string;
  type?: string;
  payload?: Record<string, unknown>;
}

const windowPositionKey = "lime-pet.windows.position.v2";
const characterSelectionKey = "lime-pet.windows.character.v2";
const reconnectDelayMs = 5000;
const dragThreshold = 6;
const windowFrame = {
  width: 460,
  height: 470
};
const runningInTauri = isTauriRuntime();

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
const petImage = requiredElement<HTMLImageElement>("#petImage");
const live2dFrame = requiredElement<HTMLIFrameElement>("#live2dFrame");
const connectionLabel = requiredElement<HTMLElement>("#connectionLabel");
const modeLabel = requiredElement<HTMLElement>("#modeLabel");
const statusCard = requiredElement<HTMLElement>("#statusCard");
const statusTitle = requiredElement<HTMLElement>("#statusTitle");
const statusMessage = requiredElement<HTMLElement>("#statusMessage");
const statusAction = requiredElement<HTMLButtonElement>("#statusAction");
const quickMenu = requiredElement<HTMLElement>("#quickMenu");
const modelDrawer = requiredElement<HTMLElement>("#modelDrawer");
const modelDrawerList = requiredElement<HTMLElement>("#modelDrawerList");
const contextMenu = requiredElement<HTMLElement>("#contextMenu");
const live2dRuntimeSummary = requiredElement<HTMLElement>("#live2dRuntimeSummary");
const diagnosticSummary = requiredElement<HTMLElement>("#diagnosticSummary");
const diagnosticChecklist = requiredElement<HTMLElement>("#diagnosticChecklist");
const providerOverviewList = requiredElement<HTMLElement>("#providerOverviewList");
const characterList = requiredElement<HTMLElement>("#characterList");

const spriteImageUrl = new URL("./assets/shared/dewy-lime-shadow.png", import.meta.url).toString();
const live2dDriver = new Live2DFrameDriver(live2dFrame);

const ambientLines = {
  connected: {
    idle: ["青橙已经在桌面守着你", "模型库切好了，我继续替你盯着 Lime"],
    walking: ["我在桌面边缘巡航", "今天这边由我来陪跑"],
    thinking: ["Lime 正在思考，我先帮你稳住桌面舞台", "有结果我会先冒泡提示"],
    done: ["刚才那件事完成啦", "如果你想继续，我还能马上切下一步"]
  },
  disconnected: {
    idle: ["我还在等 Lime 连上来", "连接恢复后我会继续同步模型动作"],
    walking: ["离线时我也会守着桌面", "主程序不在线，我先帮你待命"],
    thinking: ["现在还没连上，我先等等", "等连接恢复，我会继续同步状态"],
    done: ["连接恢复后我再继续庆祝", "先别急，我还在等 Lime 回来"]
  }
} as const;

const state = {
  config: null as LaunchConfig | null,
  socket: null as WebSocket | null,
  connected: false,
  petState: "walking" as PetState,
  currentCharacterId: defaultCharacter().id,
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
  activeLive2DModelSignature: null as string | null,
  companionDiagnostic: makeCompanionDiagnosticSnapshot({
    endpointLabel: defaultCompanionEndpoint,
    endpointConfigured: true,
    isConnected: false,
    lastConnectionReason: null,
    hasConnectedOnce: false,
    latestProviderOverview: null,
    lastProviderOverviewAt: null
  }) as CompanionDiagnosticSnapshot,
  dockSide: "right" as DockSide,
  detailsPanelOpen: false,
  modelDrawerOpen: false,
  systemStatus: {
    title: "青橙桌宠待命",
    message: "模型切换、连接反馈和运行态会在这里提示。",
    tone: "info",
    actionKey: null
  } as SystemStatusState,
  latestLive2DSummary: null as Live2DRuntimeSummary | null
};

function currentCharacter(): PetCharacterTheme {
  return characterById(state.currentCharacterId) ?? defaultCharacter();
}

function currentRenderer(): "sprite" | "live2d" {
  return characterRenderer(currentCharacter());
}

function currentCharacterIndex(): number {
  return Math.max(
    0,
    characterCatalog.characters.findIndex((character) => character.id === currentCharacter().id),
  );
}

function updateShellClasses(): void {
  shell.className = [
    "pet-shell",
    `state-${state.petState}`,
    state.connected ? "connected" : "disconnected",
    state.dragging ? "dragging" : "",
    `renderer-${currentRenderer()}`,
    `dock-${state.dockSide}`,
    state.modelDrawerOpen ? "drawer-open" : "",
    state.detailsPanelOpen ? "details-open" : ""
  ]
    .filter(Boolean)
    .join(" ");
}

function applyStageSizing(): void {
  const stageSize = currentRenderer() === "live2d"
    ? live2dStageSize(currentCharacter().live2d)
    : { width: 320, height: 320 };
  const shellWidth = Math.max(stageSize.width + 20, 440);
  const shellHeight = Math.max(stageSize.height + 20, 440);

  shell.style.setProperty("--stage-width", `${stageSize.width}px`);
  shell.style.setProperty("--stage-height", `${stageSize.height}px`);
  shell.style.setProperty("--shell-width", `${shellWidth}px`);
  shell.style.setProperty("--shell-height", `${shellHeight}px`);
}

function modeLabelFor(currentState: PetState): string {
  switch (currentState) {
    case "hidden":
      return "已隐藏";
    case "idle":
      return state.connected ? "静静陪伴" : "等待连接";
    case "walking":
      return state.connected ? "桌面巡航" : "离线守候";
    case "thinking":
      return "同步思考";
    case "done":
      return "完成庆祝";
  }
}

function defaultStatusForCurrentContext(): SystemStatusState {
  const character = currentCharacter();
  const renderer = currentRenderer();
  const isLive2D = renderer === "live2d" && Boolean(character.live2d);
  const matchingSummary = state.latestLive2DSummary?.characterId === character.id
    ? state.latestLive2DSummary
    : null;

  if (isLive2D && matchingSummary) {
    return {
      title: `${character.displayName} · ${matchingSummary.format === "cubism4" ? "Cubism 4/5" : "Cubism 2"}`,
      message: `动作组 ${matchingSummary.motionGroups.length} 个，表情 ${matchingSummary.expressionCount} 个。`,
      tone: state.connected ? "success" : "warning",
      actionKey: state.connected ? null : "reconnect"
    };
  }

  if (isLive2D) {
    return {
      title: `${character.displayName} 已选中`,
      message: "模型切换完成后，这里会显示加载格式和动作摘要。",
      tone: "info",
      actionKey: null
    };
  }

  return {
    title: `${character.displayName} 已待命`,
    message: state.connected
      ? "青橙精灵正在桌面守望，左侧快捷菜单可直接切模型和打开详情。"
      : "主程序当前未连接，连接恢复后会自动同步气泡和动作。",
    tone: state.connected ? "success" : "warning",
    actionKey: state.connected ? null : "reconnect"
  };
}

function setSystemStatus(
  title: string,
  message: string,
  tone: StatusTone = "info",
  actionKey: StatusActionKey | null = null,
): void {
  state.systemStatus = {
    title,
    message,
    tone,
    actionKey
  };
  renderSystemStatus();
}

function renderSystemStatus(): void {
  const statusState = state.systemStatus ?? defaultStatusForCurrentContext();
  const fallbackStatus = defaultStatusForCurrentContext();
  const activeStatus = statusState.title && statusState.message ? statusState : fallbackStatus;

  statusCard.classList.remove("tone-info", "tone-success", "tone-warning", "tone-error");
  statusCard.classList.add(`tone-${activeStatus.tone}`);
  statusTitle.textContent = activeStatus.title;
  statusMessage.textContent = activeStatus.message;

  if (activeStatus.actionKey === "reconnect") {
    statusAction.dataset.action = "reconnect";
    statusAction.textContent = "立即重连";
    statusAction.classList.remove("hidden");
    return;
  }

  if (activeStatus.actionKey === "retry-live2d") {
    statusAction.dataset.action = "retry-live2d";
    statusAction.textContent = "重新加载";
    statusAction.classList.remove("hidden");
    return;
  }

  statusAction.dataset.action = "";
  statusAction.classList.add("hidden");
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

function renderLive2DSummary(): void {
  const character = currentCharacter();
  if (currentRenderer() !== "live2d" || !character.live2d) {
    renderReadonlyLines(live2dRuntimeSummary, [
      "当前是青橙 sprite 形态",
      "切换到 Live2D 模型后，这里会显示格式、动作组和表情数"
    ]);
    return;
  }

  const summary = state.latestLive2DSummary?.characterId === character.id
    ? state.latestLive2DSummary
    : null;

  if (!summary) {
    renderReadonlyLines(live2dRuntimeSummary, [
      `入口: ${character.live2d.modelPath}`,
      "等待 runtime 返回模型摘要…"
    ]);
    return;
  }

  const motionSummary = summary.motionGroups.length
    ? `动作组: ${summary.motionGroups.join(", ")}`
    : "动作组: 未检测到";

  renderReadonlyLines(live2dRuntimeSummary, [
    `格式: ${summary.format === "cubism4" ? "Cubism 4/5" : "Cubism 2"}`,
    `入口: ${summary.modelPath}`,
    motionSummary,
    `表情: ${summary.expressionCount}`
  ]);
}

function makeContextCharacterButton(character: PetCharacterTheme, activeCharacterId: string): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = [
    "context-item",
    character.id === activeCharacterId ? "active" : ""
  ].filter(Boolean).join(" ");
  button.dataset.action = "switch-character";
  button.dataset.characterId = character.id;
  button.textContent = character.displayName;
  return button;
}

function makeDrawerCharacterButton(character: PetCharacterTheme, activeCharacterId: string): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = [
    "model-chip",
    character.id === activeCharacterId ? "active" : ""
  ].filter(Boolean).join(" ");
  button.dataset.action = "switch-character";
  button.dataset.characterId = character.id;
  button.innerHTML = `
    <span class="model-chip-title">${character.displayName}</span>
    <span class="model-chip-meta">
      <span class="model-chip-badge">${characterRenderer(character) === "live2d" ? "live2d" : "sprite"}</span>
      <span class="model-chip-badge">${character.id}</span>
    </span>
  `;
  return button;
}

function renderCharacterLists(): void {
  const activeCharacterId = currentCharacter().id;
  characterList.replaceChildren(
    ...characterCatalog.characters.map((character) => makeContextCharacterButton(character, activeCharacterId)),
  );
  modelDrawerList.replaceChildren(
    ...characterCatalog.characters.map((character) => makeDrawerCharacterButton(character, activeCharacterId)),
  );
}

function syncLive2DVisibility(): void {
  const character = currentCharacter();
  const renderer = characterRenderer(character);
  const isLive2D = renderer === "live2d" && Boolean(character.live2d);
  petImage.classList.toggle("hidden", isLive2D);
  live2dFrame.classList.toggle("hidden", !isLive2D);
  petImage.src = spriteImageUrl;
  petImage.alt = character.displayName;
  petButton.setAttribute("aria-label", character.displayName);

  if (isLive2D && character.live2d) {
    live2dDriver.setSource("/live2d-runtime/index.html");
    const signature = [
      character.id,
      character.live2d.modelPath,
      character.live2d.layoutMode ?? "contain",
      character.live2d.scale,
      character.live2d.offsetX,
      character.live2d.offsetY,
      character.live2d.positionX ?? "",
      character.live2d.positionY ?? "",
      character.live2d.anchorX ?? "",
      character.live2d.anchorY ?? "",
      character.live2d.stageStyle?.width ?? "",
      character.live2d.stageStyle?.height ?? ""
    ].join("|");
    if (state.activeLive2DModelSignature !== signature) {
      state.activeLive2DModelSignature = signature;
      live2dDriver.loadModel(character.live2d);
    }
    live2dDriver.setFacing(true);
    live2dDriver.setHidden(state.petState === "hidden");
    return;
  }

  if (state.activeLive2DModelSignature !== null) {
    state.activeLive2DModelSignature = null;
    live2dDriver.unloadModel();
  }
}

function render(): void {
  applyStageSizing();
  updateShellClasses();
  renderLabels();
  renderSystemStatus();
  renderBubble();
  renderCompanionDiagnostics();
  renderLive2DSummary();
  renderCharacterLists();
  syncLive2DVisibility();
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

function playCurrentLive2DStateAction(): void {
  live2dDriver.playAction(live2dStateAction(currentCharacter(), state.petState));
}

function playLive2DTapAction(tapKind: "single" | "double" | "triple"): void {
  live2dDriver.playAction(live2dTapAction(currentCharacter(), tapKind));
}

function setDetailsPanelOpen(open: boolean): void {
  state.detailsPanelOpen = open;
  contextMenu.classList.toggle("hidden", !open);
  updateShellClasses();
}

function setModelDrawerOpen(open: boolean): void {
  state.modelDrawerOpen = open;
  modelDrawer.classList.toggle("hidden", !open);
  updateShellClasses();
}

function closePanels(): void {
  setDetailsPanelOpen(false);
  setModelDrawerOpen(false);
}

function applyCharacterSelection(characterId: string, announce: boolean): void {
  const character = characterById(characterId);
  if (!character) {
    return;
  }

  state.currentCharacterId = character.id;
  state.latestLive2DSummary = null;
  localStorage.setItem(characterSelectionKey, character.id);
  render();
  playCurrentLive2DStateAction();

  setSystemStatus(
    "模型已切换",
    `${character.displayName} 已成为当前桌面舞台模型。`,
    "success",
    currentRenderer() === "live2d" ? "retry-live2d" : null,
  );

  if (announce) {
    showBubble(character.switchBubble, 1600);
  }
}

function cycleCharacter(): void {
  const nextIndex = (currentCharacterIndex() + 1) % characterCatalog.characters.length;
  const nextCharacter = characterCatalog.characters[nextIndex];
  if (nextCharacter) {
    applyCharacterSelection(nextCharacter.id, true);
  }
}

function retryCurrentLive2DModel(): void {
  const character = currentCharacter();
  if (currentRenderer() !== "live2d" || !character.live2d) {
    return;
  }

  state.latestLive2DSummary = null;
  state.activeLive2DModelSignature = null;
  setSystemStatus(
    "重新加载模型",
    `${character.displayName} 正在重新建立 runtime。`,
    "info",
    null,
  );
  render();
}

function setPetState(nextState: PetState): void {
  state.petState = nextState;
  render();
  playCurrentLive2DStateAction();
}

function saveWindowPosition(position: WindowPositionSnapshot): void {
  localStorage.setItem(windowPositionKey, JSON.stringify(position));
}

function detectDockSide(x: number, monitorPositionX: number, monitorWidth: number): DockSide {
  const shellMidX = x + Math.round(windowFrame.width / 2);
  const monitorMidX = monitorPositionX + Math.round(monitorWidth / 2);
  return shellMidX <= monitorMidX ? "left" : "right";
}

async function updateDockSide(x: number): Promise<void> {
  const monitor = await currentMonitorCompat();
  const monitorPositionX = monitor?.position.x ?? 0;
  const monitorWidth = monitor?.size.width ?? 1440;
  state.dockSide = detectDockSide(x, monitorPositionX, monitorWidth);
  updateShellClasses();
}

async function centerWindowOnCurrentMonitor(): Promise<void> {
  const monitor = await currentMonitorCompat();
  const monitorPosition = monitor?.position ?? { x: 0, y: 0 };
  const monitorSize = monitor?.size ?? { width: 1440, height: 900 };

  const x = monitorPosition.x + Math.round((monitorSize.width - windowFrame.width) / 2);
  const y = monitorPosition.y + monitorSize.height - windowFrame.height - 72;

  await appWindow.setPosition(toPhysicalPosition(x, y));
  await updateDockSide(x);
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
      await appWindow.setPosition(toPhysicalPosition(parsed.x, parsed.y));
      await updateDockSide(parsed.x);
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
  setSystemStatus("连接已断开", `${reason}，稍后自动重连。`, "error", "reconnect");
  showBubble(reason, 1600);
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
      shouldInterruptCurrentBubble ? 2200 : 1500,
    );
  }

  setSystemStatus(
    "服务商摘要已同步",
    providerOverviewBubbleText(payload),
    shouldInterruptCurrentBubble ? "warning" : "success",
    shouldInterruptCurrentBubble ? "reconnect" : null,
  );
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

function handleLive2DHostEvent(message: Live2DHostEnvelope): void {
  if (message.source !== "lime-pet-live2d" || typeof message.type !== "string") {
    return;
  }

  const payload = message.payload ?? {};
  const currentCharacterId = currentCharacter().id;

  switch (message.type) {
    case "model-loading":
      setSystemStatus(
        "模型加载中",
        `${currentCharacter().displayName} 正在建立 ${payload.format === "cubism4" ? "Cubism 4/5" : "Cubism 2"} runtime。`,
        "info",
        null,
      );
      renderLive2DSummary();
      break;
    case "model-loaded": {
      const motionGroups = Array.isArray(payload.motionGroups)
        ? payload.motionGroups.filter((item): item is string => typeof item === "string")
        : [];
      const summary: Live2DRuntimeSummary = {
        characterId: currentCharacterId,
        modelPath: typeof payload.modelPath === "string" ? payload.modelPath : "",
        format: typeof payload.format === "string" ? payload.format : "cubism2",
        motionGroups,
        expressionCount: typeof payload.expressionCount === "number" ? payload.expressionCount : 0
      };
      state.latestLive2DSummary = summary;
      setSystemStatus(
        "模型已就绪",
        `${currentCharacter().displayName} 已加载完成，可用动作组 ${motionGroups.length} 个。`,
        "success",
        null,
      );
      render();
      break;
    }
    case "model-error":
      state.latestLive2DSummary = null;
      setSystemStatus(
        "模型加载失败",
        typeof payload.message === "string"
          ? payload.message
          : `${currentCharacter().displayName} 模型未能加载成功。`,
        "error",
        "retry-live2d",
      );
      renderLive2DSummary();
      break;
    case "model-unloaded":
      state.latestLive2DSummary = null;
      renderLive2DSummary();
      break;
    default:
      break;
  }
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
    setSystemStatus("协议版本不兼容", `收到版本 ${String(envelope.protocol_version)}，当前版本 ${String(state.config?.protocol_version ?? "未知")}`, "error");
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
    case "pet.live2d_action":
      live2dDriver.playAction(live2dEnvelopeAction(currentCharacter(), envelope.payload));
      break;
    default:
      break;
  }
}

async function connectSocket(): Promise<void> {
  if (!state.config?.endpoint) {
    state.endpointLabel = runningInTauri ? "未配置" : "浏览器预览";
    state.lastConnectionReason = runningInTauri
      ? "未配置 Lime Companion 地址"
      : "浏览器预览模式不会连接 Lime Companion";
    render();
    setSystemStatus(
      runningInTauri ? "连接未配置" : "浏览器预览模式",
      runningInTauri
        ? "当前没有 Companion 地址，Windows 桌宠不会自动连线。"
        : "当前页面运行在浏览器预览里，已跳过 Tauri 窗口控制和 Companion 连接。",
      runningInTauri ? "error" : "info",
    );
    showBubble(runningInTauri ? "未配置 Lime Companion 地址" : "浏览器预览模式已开启", 1800);
    return;
  }

  if (state.socket && state.socket.readyState === WebSocket.OPEN) {
    return;
  }

  clearReconnectTimer();
  setSystemStatus("正在连接 Lime", `${state.config.endpoint} · 正在建立 Companion 会话。`, "info");

  const socket = new WebSocket(state.config.endpoint);
  state.socket = socket;

  socket.addEventListener("open", () => {
    state.connected = true;
    state.endpointLabel = state.config?.endpoint ?? state.endpointLabel;
    state.lastConnectionReason = null;
    state.hasConnectedOnce = true;
    render();
    sendReadyEvent();
    setSystemStatus(
      "Lime 已连接",
      `${currentCharacter().displayName} 现在可以同步状态、摘要和 Live2D 动作。`,
      "success",
      null,
    );
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
    scheduleReconnect("Windows 桌宠连接已断开");
  });

  socket.addEventListener("error", () => {
    socket.close();
  });
}

async function handlePetTap(): Promise<void> {
  playLive2DTapAction("single");

  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    setSystemStatus("连接未就绪", "当前还没有连上 Lime，我先尝试重新建立连接。", "warning", "reconnect");
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("正在唤起 Lime…", 1200);
  setSystemStatus("正在唤起主应用", "这次点击会触发对话入口和桌宠点击事件。", "info");
  sendTapEvents();
}

function requestPetCheer(source: string): void {
  playLive2DTapAction("double");

  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    setSystemStatus("连接未就绪", "还没连接主应用，暂时无法请求鼓励。", "warning", "reconnect");
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("青柠想一句鼓励给你…", 1400);
  setSystemStatus("正在请求一句鼓励", "双击动作已触发，主应用会返回一条青橙式鼓励。", "info");
  sendEnvelope("pet.request_pet_cheer", { source });
}

function requestPetNextStep(source: string): void {
  playLive2DTapAction("triple");

  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    setSystemStatus("连接未就绪", "还没连接主应用，暂时无法请求下一步建议。", "warning", "reconnect");
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("青柠在想你的下一步…", 1400);
  setSystemStatus("正在请求下一步", "三击动作已触发，主应用会尝试给出下一步建议。", "info");
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
  closePanels();
  setPetState("hidden");
  setSystemStatus("桌宠已隐藏", "主窗口已隐藏，你可以从主应用重新唤起。", "info");
  await appWindow.hide();
}

function reconnectFromMenu(): void {
  clearReconnectTimer();
  setSystemStatus("正在重连 Lime", "手动重连已触发，我会立刻重新建立 Companion 会话。", "info");
  showBubble("正在尝试重新连接 Lime…", 1200);
  void connectSocket();
}

function requestProviderOverviewSync(source: string): void {
  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    setSystemStatus("连接未就绪", "当前无法同步服务商摘要，我先尝试重连。", "warning", "reconnect");
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("正在请求同步桌宠摘要…", 1200);
  setSystemStatus("正在同步服务商摘要", "请求已经发出，桌宠诊断面板会跟着刷新。", "info");
  sendEnvelope("pet.request_provider_overview_sync", { source });
}

function openProviderSettings(source: string): void {
  if (!state.connected) {
    showBubble("Lime 还没连上，我先等它", 1400);
    setSystemStatus("连接未就绪", "当前无法打开服务商设置，我先尝试重连。", "warning", "reconnect");
    clearReconnectTimer();
    void connectSocket();
    return;
  }

  showBubble("正在打开 AI 服务商设置…", 1200);
  setSystemStatus("正在打开设置", "服务商设置面板会在主应用侧弹出。", "info");
  sendEnvelope("pet.open_provider_settings", { source });
}

async function quitApp(): Promise<void> {
  closePanels();
  await appWindow.close();
}

function handleUIAction(action: string, target: HTMLElement): void {
  const characterId = target.dataset.characterId;

  switch (action) {
    case "switch-character":
      if (characterId) {
        applyCharacterSelection(characterId, true);
      }
      break;
    case "toggle-model-drawer":
      setModelDrawerOpen(!state.modelDrawerOpen);
      if (state.modelDrawerOpen) {
        setDetailsPanelOpen(false);
      }
      break;
    case "toggle-details":
      setDetailsPanelOpen(!state.detailsPanelOpen);
      if (state.detailsPanelOpen) {
        setModelDrawerOpen(false);
      }
      break;
    case "cycle-character":
      closePanels();
      cycleCharacter();
      break;
    case "request-cheer":
      closePanels();
      requestPetCheer("quick_menu");
      break;
    case "reconnect":
      closePanels();
      reconnectFromMenu();
      break;
    case "retry-live2d":
      closePanels();
      retryCurrentLive2DModel();
      break;
    case "sync-provider-overview":
      closePanels();
      requestProviderOverviewSync("ui");
      break;
    case "provider-settings":
      closePanels();
      openProviderSettings("ui");
      break;
    case "recenter":
      closePanels();
      void centerWindowOnCurrentMonitor().then(() => {
        setSystemStatus("桌宠已回中", "窗口已经重新定位到当前屏幕中央偏下位置。", "success");
        showBubble("回到屏幕中央啦", 1200);
      });
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
}

function bindActionContainer(container: HTMLElement): void {
  container.addEventListener("click", (event) => {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>("[data-action]");
    const action = target?.dataset.action;

    if (!target || !action) {
      return;
    }

    handleUIAction(action, target);
  });
}

function bindWindowGestures(): void {
  petButton.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) {
      return;
    }

    closePanels();
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
    setSystemStatus("拖拽摆放中", "把桌宠拖到你喜欢的位置，我会记住这次停靠方向。", "info");
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
    setDetailsPanelOpen(true);
    setModelDrawerOpen(false);
  });

  document.addEventListener("pointerdown", (event) => {
    const target = event.target as Node | null;
    if (!target) {
      return;
    }

    const shouldKeepPanelsOpen =
      contextMenu.contains(target) ||
      modelDrawer.contains(target) ||
      quickMenu.contains(target) ||
      statusAction.contains(target);

    if (!shouldKeepPanelsOpen) {
      closePanels();
    }
  });

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closePanels();
      hideBubble();
    }
  });

  window.addEventListener("message", (event) => {
    if (event.data && typeof event.data === "object") {
      handleLive2DHostEvent(event.data as Live2DHostEnvelope);
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
    void updateDockSide(payload.x);
  });
}

async function bootstrap(): Promise<void> {
  state.config = await invokeCompat<LaunchConfig>("load_launch_config");
  state.endpointLabel = state.config.endpoint ?? "未配置";
  const storedCharacterId = localStorage.getItem(characterSelectionKey);
  state.currentCharacterId = characterById(storedCharacterId)?.id ?? defaultCharacter().id;

  bindActionContainer(contextMenu);
  bindActionContainer(quickMenu);
  bindActionContainer(modelDrawer);
  bindActionContainer(statusAction);
  bindWindowGestures();
  restartAmbientLoop();

  render();
  await initializeWindowBehavior();
  await connectSocket();

  setSystemStatus(
    "青橙桌宠已启动",
    "单击打开 Lime，双击要一句鼓励，三击拿下一步建议，左侧快捷菜单可以直接切模型。",
    "info",
    null,
  );
  showBubble("左侧快捷菜单能直接切模型，右键还能展开完整详情面板", 2400);
}

void bootstrap();
