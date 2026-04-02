import Foundation

struct PetCompanionDiagnosticSnapshot {
    let connectionLine: String
    let endpointLine: String
    let syncLine: String
    let lastSyncLine: String
    let actionLine: String
    let checkLines: [String]
    let providerLines: [String]

    static let placeholder = PetCompanionDiagnosticSnapshot(
        connectionLine: "连接：等待连接",
        endpointLine: "地址：\(defaultCompanionEndpoint)",
        syncLine: "同步：等待 Lime 推送脱敏摘要",
        lastSyncLine: "最近同步：尚未同步",
        actionLine: "建议：先启动 Lime，并保持 Companion 宿主在线",
        checkLines: [
            "宿主监听：等待桌宠连接",
            "桌宠连接：尚未建立",
            "能力声明：连接后会自动上报 \(petCompanionCapabilities.count) 项能力",
            "摘要准备：桌宠只接收脱敏后的服务商摘要"
        ],
        providerLines: [
            "尚未收到服务商摘要",
            "桌宠不会读取 API Key、UUID 或 Base URL",
            "回到 Lime 的 AI 服务商设置后可手动触发同步"
        ]
    )
}

struct PetCompanionDiagnosticInput {
    let endpointConfigured: Bool
    let endpointLabel: String
    let isConnected: Bool
    let lastConnectionReason: String?
    let hasConnectedOnce: Bool
    let latestProviderOverview: CompanionProviderOverviewPayload?
    let lastProviderOverviewAt: Date?
}

func makePetCompanionDiagnosticSnapshot(
    input: PetCompanionDiagnosticInput
) -> PetCompanionDiagnosticSnapshot {
    let listenerLine: String
    if !input.endpointConfigured {
        listenerLine = "宿主监听：未配置 Companion 地址"
    } else if input.isConnected {
        listenerLine = "宿主监听：已接受桌宠连接"
    } else {
        listenerLine = "宿主监听：等待 \(input.endpointLabel) 接受连接"
    }

    let connectionLine: String
    if input.isConnected {
        connectionLine = "连接：已连接"
    } else if let lastConnectionReason = input.lastConnectionReason, !lastConnectionReason.isEmpty {
        connectionLine = "连接：离线（\(lastConnectionReason)）"
    } else {
        connectionLine = "连接：等待连接"
    }

    let capabilityLine: String
    if input.isConnected {
        capabilityLine = "能力声明：已向 Lime 上报 \(petCompanionCapabilities.count) 项桌宠能力"
    } else if input.hasConnectedOnce {
        capabilityLine = "能力声明：最近一次连接已上报 \(petCompanionCapabilities.count) 项能力"
    } else {
        capabilityLine = "能力声明：连接后会自动上报 \(petCompanionCapabilities.count) 项能力"
    }

    let summaryLine: String
    let syncLine: String
    let actionLine: String
    let providerLines: [String]

    if let overview = input.latestProviderOverview {
        if overview.totalProviderCount == 0 {
            summaryLine = "摘要准备：已同步，但当前没有配置任何服务商"
            syncLine = "同步：已收到空摘要"
            actionLine = "建议：先在 Lime 中配置至少一个 AI 服务商"
            providerLines = [
                "总数：0 个服务商",
                "当前没有可供桌宠感知的 AI 服务商",
                "桌宠不会读取 API Key、UUID 或 Base URL"
            ]
        } else {
            let healthLine = "可用：\(overview.availableProviderCount)/\(overview.totalProviderCount)"
            let attentionLine = overview.needsAttentionProviderCount > 0
                ? "需关注：\(overview.needsAttentionProviderCount) 个"
                : "需关注：0 个"
            summaryLine = overview.needsAttentionProviderCount > 0
                ? "摘要准备：已同步，但有服务商需要关注"
                : "摘要准备：脱敏服务商摘要已就绪"
            syncLine = "同步：已收到 \(healthLine) 的桌宠摘要"
            actionLine = petProviderActionLine(isConnected: input.isConnected, overview: overview)

            var lines = [
                "总数：\(overview.totalProviderCount) 个服务商",
                healthLine,
                attentionLine
            ]
            lines.append(contentsOf: overview.providers.prefix(4).map(petProviderPreviewLine))
            lines.append("桌宠不会读取 API Key、UUID 或 Base URL")
            providerLines = lines
        }
    } else {
        summaryLine = "摘要准备：等待 Lime 推送脱敏后的服务商摘要"
        syncLine = "同步：尚未收到服务商同步"
        actionLine = input.endpointConfigured
            ? "建议：先启动 Lime，再到 AI 服务商设置执行一次同步"
            : "建议：启动桌宠时传入 Companion 地址"
        providerLines = PetCompanionDiagnosticSnapshot.placeholder.providerLines
    }

    return PetCompanionDiagnosticSnapshot(
        connectionLine: connectionLine,
        endpointLine: "地址：\(input.endpointLabel)",
        syncLine: syncLine,
        lastSyncLine: "最近同步：\(petLastSyncLabel(input.lastProviderOverviewAt))",
        actionLine: actionLine,
        checkLines: [
            listenerLine,
            input.isConnected ? "桌宠连接：已建立" : "桌宠连接：尚未建立",
            capabilityLine,
            summaryLine
        ],
        providerLines: providerLines
    )
}

func petProviderOverviewBubbleText(for overview: CompanionProviderOverviewPayload) -> String {
    if overview.totalProviderCount == 0 {
        return "还没有配置 AI 服务商，右键可打开设置"
    }

    if overview.availableProviderCount == 0 {
        return "AI 服务商暂不可用，右键可打开设置"
    }

    if overview.needsAttentionProviderCount > 0 {
        return "已同步 \(overview.availableProviderCount) 个可用服务商，\(overview.needsAttentionProviderCount) 个需要关注"
    }

    return "已同步 \(overview.availableProviderCount) 个可用 AI 服务商"
}

private func petProviderActionLine(
    isConnected: Bool,
    overview: CompanionProviderOverviewPayload
) -> String {
    if !isConnected {
        return "建议：先恢复桌宠与 Lime Companion 的连接"
    }
    if overview.availableProviderCount == 0 {
        return "建议：检查服务商凭证、Base URL 或网络状态"
    }
    if overview.needsAttentionProviderCount > 0 {
        return "建议：优先处理需要关注的服务商，再回桌宠确认"
    }
    return "建议：当前接入完成，点桌宠即可回到 Lime 对话"
}

private func petProviderPreviewLine(for provider: CompanionProviderSummary) -> String {
    let suffix: String
    if provider.needsAttention {
        suffix = "需关注"
    } else if provider.available {
        suffix = "可用"
    } else {
        suffix = "未就绪"
    }

    return "\(provider.displayName) · \(provider.healthyCount)/\(provider.totalCount) · \(suffix)"
}

private func petLastSyncLabel(_ date: Date?) -> String {
    guard let date else { return "尚未同步" }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm:ss" : "MM-dd HH:mm"
    return formatter.string(from: date)
}
