import Foundation

let defaultCompanionEndpoint = "ws://127.0.0.1:45554/companion/pet"
let companionProtocolVersion = 1

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
}

enum CompanionEventType: String {
    case ready = "pet.ready"
    case clicked = "pet.clicked"
    case openChat = "pet.open_chat"
    case dismissed = "pet.dismissed"
}

enum IncomingCommand {
    case show
    case hide
    case stateChanged(PetState)
    case showBubble(text: String, autoHideMs: Int?)
    case openChatAnchor
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

    static func current(arguments: [String] = CommandLine.arguments) -> LaunchConfiguration {
        var endpointString = defaultCompanionEndpoint
        var clientId = "lime"
        var protocolVersion = companionProtocolVersion
        var debugWindowSurface = false

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
            default:
                continue
            }
        }

        return LaunchConfiguration(
            endpoint: URL(string: endpointString),
            clientId: clientId,
            protocolVersion: protocolVersion,
            debugWindowSurface: debugWindowSurface
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
