import Foundation

let defaultCompanionEndpoint = "ws://127.0.0.1:45554/companion/pet"
let companionProtocolVersion = 1
let petCompanionCapabilities = [
    "bubble",
    "movement",
    "tap-open-chat",
    "drag-reposition",
    "reactive-animations",
    "perch-memory",
    "dock-presets",
    "ambient-dialogue",
    "character-themes",
    "provider-overview",
    "provider-sync-request",
    "open-provider-settings",
    "chat-request",
    "chat-reset",
    "voice-chat-request",
    "bubble-speech",
    "multi-tap-actions",
    "live2d-renderer",
    "live2d-expressions"
]

enum PetState: String, CaseIterable, Codable {
    case hidden
    case idle
    case walking
    case thinking
    case done
}

enum CompanionCommandType: String {
    case show = "pet.show"
    case hide = "pet.hide"
    case stateChanged = "pet.state_changed"
    case showBubble = "pet.show_bubble"
    case openChatAnchor = "pet.open_chat_anchor"
    case providerOverview = "pet.provider_overview"
    case live2dAction = "pet.live2d_action"
}

enum CompanionEventType: String {
    case ready = "pet.ready"
    case clicked = "pet.clicked"
    case openChat = "pet.open_chat"
    case dismissed = "pet.dismissed"
    case requestProviderOverviewSync = "pet.request_provider_overview_sync"
    case openProviderSettings = "pet.open_provider_settings"
    case requestPetCheer = "pet.request_pet_cheer"
    case requestPetNextStep = "pet.request_pet_next_step"
    case requestChatReply = "pet.request_chat_reply"
    case requestChatReset = "pet.request_chat_reset"
    case requestVoiceChat = "pet.request_voice_chat"
}

enum IncomingCommand {
    case show
    case hide
    case stateChanged(PetState)
    case showBubble(text: String, autoHideMs: Int?)
    case openChatAnchor
    case providerOverview(CompanionProviderOverviewPayload)
    case live2dAction(CompanionLive2DActionPayload)
}

enum PetIPCConnectionStatus {
    case connected(endpoint: String)
    case disconnected(reason: String)
}

@MainActor
protocol PetIPCClientDelegate: AnyObject {
    func petIPCClient(_ client: PetIPCClient, didChange status: PetIPCConnectionStatus)
    func petIPCClient(_ client: PetIPCClient, didReceive command: IncomingCommand)
}

struct LaunchConfiguration {
    let endpoint: URL?
    let clientId: String
    let protocolVersion: Int
    let debugWindowSurface: Bool
    let controlPlaneBaseURL: URL?
    let tenantId: String

    static func current(arguments: [String] = CommandLine.arguments) -> LaunchConfiguration {
        let environment = ProcessInfo.processInfo.environment
        var endpointString = defaultCompanionEndpoint
        var clientId = "lime"
        var protocolVersion = companionProtocolVersion
        var debugWindowSurface = false
        var controlPlaneBaseURLString = environment["LIME_CONTROL_PLANE_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var tenantId = environment["LIME_TENANT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tenant-0001"

        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--connect":
                if let value = iterator.next() {
                    endpointString = value
                }
            case "--client-id":
                if let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    clientId = value
                }
            case "--protocol-version":
                if let value = iterator.next(), let parsed = Int(value) {
                    protocolVersion = parsed
                }
            case "--debug-window-surface":
                debugWindowSurface = true
            case "--control-plane-base-url":
                if let value = iterator.next() {
                    controlPlaneBaseURLString = value
                }
            case "--tenant-id":
                if let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tenantId = value
                }
            default:
                continue
            }
        }

        return LaunchConfiguration(
            endpoint: URL(string: endpointString),
            clientId: clientId,
            protocolVersion: protocolVersion,
            debugWindowSurface: debugWindowSurface,
            controlPlaneBaseURL: URL(string: controlPlaneBaseURLString),
            tenantId: tenantId
        )
    }
}

struct OutboundEnvelope<Payload: Encodable>: Encodable {
    let protocolVersion: Int
    let event: String
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case event
        case payload
    }
}

struct ReadyPayload: Encodable {
    let clientId: String
    let platform: String
    let capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case platform
        case capabilities
    }
}

struct InteractionPayload: Encodable {
    let source: String
}

struct PetChatRequestPayload: Encodable {
    let text: String
    let source: String
}

struct StateChangedPayload: Decodable {
    let state: PetState
}

struct BubblePayload: Decodable {
    let text: String
    let autoHideMs: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case autoHideMs = "auto_hide_ms"
    }
}

struct CompanionProviderSummary: Decodable {
    let providerType: String
    let displayName: String
    let totalCount: Int
    let healthyCount: Int
    let available: Bool
    let needsAttention: Bool

    enum CodingKeys: String, CodingKey {
        case providerType = "provider_type"
        case displayName = "display_name"
        case totalCount = "total_count"
        case healthyCount = "healthy_count"
        case available
        case needsAttention = "needs_attention"
    }
}

struct CompanionProviderOverviewPayload: Decodable {
    let providers: [CompanionProviderSummary]
    let totalProviderCount: Int
    let availableProviderCount: Int
    let needsAttentionProviderCount: Int

    enum CodingKeys: String, CodingKey {
        case providers
        case totalProviderCount = "total_provider_count"
        case availableProviderCount = "available_provider_count"
        case needsAttentionProviderCount = "needs_attention_provider_count"
    }
}

enum CompanionLive2DExpressionValue: Decodable, Hashable {
    case index(Int)
    case tag(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .index(intValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            self = .tag(stringValue)
            return
        }
        throw DecodingError.typeMismatch(
            CompanionLive2DExpressionValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported Live2D expression value"
            )
        )
    }
}

struct CompanionLive2DActionPayload: Decodable {
    let expressions: [CompanionLive2DExpressionValue]
    let emotionTags: [String]
    let motionGroup: String?
    let motionIndex: Int?

    enum CodingKeys: String, CodingKey {
        case expressions
        case emotionTags = "emotion_tags"
        case motionGroup = "motion_group"
        case motionIndex = "motion_index"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expressions = try container.decodeIfPresent([CompanionLive2DExpressionValue].self, forKey: .expressions) ?? []
        emotionTags = try container.decodeIfPresent([String].self, forKey: .emotionTags) ?? []
        motionGroup = try container.decodeIfPresent(String.self, forKey: .motionGroup)
        motionIndex = try container.decodeIfPresent(Int.self, forKey: .motionIndex)
    }
}

struct InboundEnvelope {
    let protocolVersion: Int
    let event: String
    let payload: Any

    init?(text: String) {
        guard
            let data = text.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let protocolVersion = raw["protocol_version"] as? Int,
            let event = raw["event"] as? String
        else {
            return nil
        }

        self.protocolVersion = protocolVersion
        self.event = event
        self.payload = raw["payload"] ?? [:]
    }
}

func decodePayload<T: Decodable>(_ type: T.Type, from value: Any) -> T? {
    guard JSONSerialization.isValidJSONObject(value) else {
        return nil
    }

    guard
        let data = try? JSONSerialization.data(withJSONObject: value),
        let decoded = try? JSONDecoder().decode(type, from: data)
    else {
        return nil
    }

    return decoded
}
