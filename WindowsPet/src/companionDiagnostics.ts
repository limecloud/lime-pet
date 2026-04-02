export interface ProviderOverviewItem {
  provider_type: string;
  display_name: string;
  total_count: number;
  healthy_count: number;
  available: boolean;
  needs_attention: boolean;
}

export interface ProviderOverviewPayload {
  providers: ProviderOverviewItem[];
  total_provider_count: number;
  available_provider_count: number;
  needs_attention_provider_count: number;
}

export interface CompanionDiagnosticSnapshot {
  connectionLine: string;
  endpointLine: string;
  syncLine: string;
  lastSyncLine: string;
  actionLine: string;
  checkLines: string[];
  providerLines: string[];
}

interface CompanionDiagnosticSnapshotInput {
  endpointLabel: string;
  endpointConfigured: boolean;
  isConnected: boolean;
  lastConnectionReason: string | null;
  hasConnectedOnce: boolean;
  latestProviderOverview: ProviderOverviewPayload | null;
  lastProviderOverviewAt: number | null;
}

export const defaultCompanionEndpoint = "ws://127.0.0.1:45554/companion/pet";

export const petCompanionCapabilities = [
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
  "multi-tap-actions",
  "live2d-renderer",
  "live2d-expressions"
] as const;

export function providerOverviewFingerprint(payload: ProviderOverviewPayload): string {
  const providerSegments = payload.providers.map(
    (provider) =>
      `${provider.provider_type}:${provider.healthy_count}/${provider.total_count}:${provider.available ? 1 : 0}:${provider.needs_attention ? 1 : 0}`,
  );

  return [
    String(payload.total_provider_count),
    String(payload.available_provider_count),
    String(payload.needs_attention_provider_count),
    ...providerSegments
  ].join("|");
}

export function providerOverviewBubbleText(payload: ProviderOverviewPayload): string {
  if (payload.total_provider_count === 0) {
    return "还没有配置 AI 服务商，右键可打开设置";
  }

  if (payload.available_provider_count === 0) {
    return "AI 服务商暂不可用，右键可打开设置";
  }

  if (payload.needs_attention_provider_count > 0) {
    return `已同步 ${payload.available_provider_count} 个可用服务商，${payload.needs_attention_provider_count} 个需要关注`;
  }

  return `已同步 ${payload.available_provider_count} 个可用 AI 服务商`;
}

export function makeCompanionDiagnosticSnapshot(
  input: CompanionDiagnosticSnapshotInput,
): CompanionDiagnosticSnapshot {
  const listenerLine = !input.endpointConfigured
    ? "宿主监听：未配置 Companion 地址"
    : input.isConnected
      ? "宿主监听：已接受桌宠连接"
      : `宿主监听：等待 ${input.endpointLabel} 接受连接`;

  const connectionLine = input.isConnected
    ? "连接：已连接"
    : input.lastConnectionReason
      ? `连接：离线（${input.lastConnectionReason}）`
      : "连接：等待连接";

  const capabilityLine = input.isConnected
    ? `能力声明：已向 Lime 上报 ${petCompanionCapabilities.length} 项桌宠能力`
    : input.hasConnectedOnce
      ? `能力声明：最近一次连接已上报 ${petCompanionCapabilities.length} 项能力`
      : `能力声明：连接后会自动上报 ${petCompanionCapabilities.length} 项能力`;

  let summaryLine = "摘要准备：等待 Lime 推送脱敏后的服务商摘要";
  let syncLine = "同步：尚未收到服务商同步";
  let actionLine = !input.endpointConfigured
    ? "建议：启动桌宠时传入 Companion 地址"
    : "建议：先启动 Lime，再到 AI 服务商设置执行一次同步";
  let providerLines = [
    "尚未收到服务商摘要",
    "桌宠不会读取 API Key、UUID 或 Base URL",
    "回到 Lime 的 AI 服务商设置后可手动触发同步"
  ];

  if (input.latestProviderOverview) {
    const overview = input.latestProviderOverview;

    if (overview.total_provider_count === 0) {
      summaryLine = "摘要准备：已同步，但当前没有配置任何服务商";
      syncLine = "同步：已收到空摘要";
      actionLine = "建议：先在 Lime 中配置至少一个 AI 服务商";
      providerLines = [
        "总数：0 个服务商",
        "当前没有可供桌宠感知的 AI 服务商",
        "桌宠不会读取 API Key、UUID 或 Base URL"
      ];
    } else {
      const healthLine = `可用：${overview.available_provider_count}/${overview.total_provider_count}`;
      const attentionLine = overview.needs_attention_provider_count > 0
        ? `需关注：${overview.needs_attention_provider_count} 个`
        : "需关注：0 个";

      summaryLine = overview.needs_attention_provider_count > 0
        ? "摘要准备：已同步，但有服务商需要关注"
        : "摘要准备：脱敏服务商摘要已就绪";
      syncLine = `同步：已收到 ${healthLine} 的桌宠摘要`;
      actionLine = providerActionLine({
        isConnected: input.isConnected,
        overview
      });
      providerLines = [
        `总数：${overview.total_provider_count} 个服务商`,
        healthLine,
        attentionLine,
        ...overview.providers.slice(0, 4).map(providerPreviewLine),
        "桌宠不会读取 API Key、UUID 或 Base URL"
      ];
    }
  }

  return {
    connectionLine,
    endpointLine: `地址：${input.endpointLabel}`,
    syncLine,
    lastSyncLine: `最近同步：${lastSyncLabel(input.lastProviderOverviewAt)}`,
    actionLine,
    checkLines: [
      listenerLine,
      input.isConnected ? "桌宠连接：已建立" : "桌宠连接：尚未建立",
      capabilityLine,
      summaryLine
    ],
    providerLines
  };
}

function providerActionLine(input: {
  isConnected: boolean;
  overview: ProviderOverviewPayload;
}): string {
  if (!input.isConnected) {
    return "建议：先恢复桌宠与 Lime Companion 的连接";
  }

  if (input.overview.available_provider_count === 0) {
    return "建议：检查服务商凭证、Base URL 或网络状态";
  }

  if (input.overview.needs_attention_provider_count > 0) {
    return "建议：优先处理需要关注的服务商，再回桌宠确认";
  }

  return "建议：当前接入完成，点桌宠即可回到 Lime 对话";
}

function providerPreviewLine(provider: ProviderOverviewItem): string {
  const suffix = provider.needs_attention
    ? "需关注"
    : provider.available
      ? "可用"
      : "未就绪";

  return `${provider.display_name} · ${provider.healthy_count}/${provider.total_count} · ${suffix}`;
}

function lastSyncLabel(timestamp: number | null): string {
  if (!timestamp) {
    return "尚未同步";
  }

  const date = new Date(timestamp);
  const now = new Date();
  const sameDay = date.toDateString() === now.toDateString();

  return new Intl.DateTimeFormat("zh-CN", sameDay
    ? {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hour12: false
      }
    : {
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false
      }).format(date);
}
