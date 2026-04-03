import Foundation

@MainActor
final class PetIPCClient: NSObject {
    private let configuration: LaunchConfiguration
    private weak var delegate: PetIPCClientDelegate?
    private lazy var session = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: OperationQueue.main
    )

    private var task: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?

    init(configuration: LaunchConfiguration, delegate: PetIPCClientDelegate) {
        self.configuration = configuration
        self.delegate = delegate
    }

    func connect() {
        guard task == nil else { return }
        guard let endpoint = configuration.endpoint else {
            delegate?.petIPCClient(self, didChange: .disconnected(reason: "未配置 Lime Companion 地址"))
            return
        }

        let task = session.webSocketTask(with: endpoint)
        self.task = task
        task.resume()
    }

    func reconnect() {
        disconnect()
        connect()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func sendTapEvents() {
        let payload = InteractionPayload(source: "pet")
        send(event: .clicked, payload: payload)
        send(event: .openChat, payload: payload)
    }

    func openProviderSettings(source: String) {
        send(event: .openProviderSettings, payload: InteractionPayload(source: source))
    }

    func requestProviderOverviewSync(source: String) {
        send(
            event: .requestProviderOverviewSync,
            payload: InteractionPayload(source: source)
        )
    }

    func requestPetCheer(source: String) {
        send(event: .requestPetCheer, payload: InteractionPayload(source: source))
    }

    func requestPetNextStep(source: String) {
        send(event: .requestPetNextStep, payload: InteractionPayload(source: source))
    }

    func requestChatReply(text: String, source: String) {
        send(
            event: .requestChatReply,
            payload: PetChatRequestPayload(text: text, source: source)
        )
    }

    func requestChatReset(source: String) {
        send(event: .requestChatReset, payload: InteractionPayload(source: source))
    }

    func requestVoiceChat(source: String) {
        send(event: .requestVoiceChat, payload: InteractionPayload(source: source))
    }

    private func sendReadyEvent() {
        send(
            event: .ready,
            payload: ReadyPayload(
                clientId: configuration.clientId,
                platform: "macos",
                capabilities: petCompanionCapabilities
            )
        )
    }

    private func send<Payload: Encodable>(event: CompanionEventType, payload: Payload) {
        guard let task else { return }

        let envelope = OutboundEnvelope(
            protocolVersion: configuration.protocolVersion,
            event: event.rawValue,
            payload: payload
        )

        guard
            let data = try? JSONEncoder().encode(envelope),
            let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.petIPCClient(self, didChange: .disconnected(reason: "发送失败: \(error.localizedDescription)"))
                self.scheduleReconnect()
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop()
                case .failure(let error):
                    self.delegate?.petIPCClient(self, didChange: .disconnected(reason: "连接中断: \(error.localizedDescription)"))
                    self.task = nil
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(decoding: data, as: UTF8.self)
        @unknown default:
            return
        }

        guard let envelope = InboundEnvelope(text: text) else {
            return
        }

        guard envelope.protocolVersion == configuration.protocolVersion else {
            delegate?.petIPCClient(self, didChange: .disconnected(reason: "协议版本不兼容：\(envelope.protocolVersion)"))
            return
        }

        switch envelope.event {
        case CompanionCommandType.show.rawValue:
            delegate?.petIPCClient(self, didReceive: .show)
        case CompanionCommandType.hide.rawValue:
            delegate?.petIPCClient(self, didReceive: .hide)
        case CompanionCommandType.stateChanged.rawValue:
            if let payload = decodePayload(StateChangedPayload.self, from: envelope.payload) {
                delegate?.petIPCClient(self, didReceive: .stateChanged(payload.state))
            }
        case CompanionCommandType.showBubble.rawValue:
            if let payload = decodePayload(BubblePayload.self, from: envelope.payload) {
                delegate?.petIPCClient(
                    self,
                    didReceive: .showBubble(text: payload.text, autoHideMs: payload.autoHideMs)
                )
            }
        case CompanionCommandType.openChatAnchor.rawValue:
            delegate?.petIPCClient(self, didReceive: .openChatAnchor)
        case CompanionCommandType.providerOverview.rawValue:
            if let payload = decodePayload(CompanionProviderOverviewPayload.self, from: envelope.payload) {
                delegate?.petIPCClient(self, didReceive: .providerOverview(payload))
            }
        case CompanionCommandType.live2dAction.rawValue:
            if let payload = decodePayload(CompanionLive2DActionPayload.self, from: envelope.payload) {
                delegate?.petIPCClient(self, didReceive: .live2dAction(payload))
            }
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard configuration.endpoint != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.task = nil
                self.connect()
            }
        }
    }
}

extension PetIPCClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let endpoint = self.configuration.endpoint?.absoluteString {
                self.delegate?.petIPCClient(self, didChange: .connected(endpoint: endpoint))
            }
            self.sendReadyEvent()
            self.receiveLoop()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.task = nil
            self.delegate?.petIPCClient(self, didChange: .disconnected(reason: "连接已关闭"))
            self.scheduleReconnect()
        }
    }
}
