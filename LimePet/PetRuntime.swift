import AppKit
import Combine
import SwiftUI

private let petTapThreshold: CGFloat = 10

@MainActor
final class PetSceneModel: ObservableObject {
    @Published var state: PetState = .walking
    @Published var bubbleText: String?
    @Published var isFacingRight = true
    @Published var isConnected = false
    @Published var connectionLabel = "等待连接"
    @Published var modeLabel = "中央巡航"
    @Published var character: PetCharacterTheme = .fallback
    @Published var isDragging = false
    @Published var isMoving = true
    @Published var bodyBob: CGFloat = 0
    @Published var bodyStretch: CGFloat = 1
    @Published var eyeOpenScale: CGFloat = 1
    @Published var tailAngle: Double = 0
    @Published var haloPulse: Double = 0
    @Published var footPhase: Double = 0
    @Published var moodGlow: Double = 0
    @Published var interactionPulse: CGFloat = 0
    @Published var headTilt: Double = 0
    @Published var gazeOffset: CGFloat = 0
    @Published var earLift: CGFloat = 0
    @Published var whiskerSwing: Double = 0
    @Published var mouthCurve: CGFloat = 0.5
    @Published var companionDiagnostic = PetCompanionDiagnosticSnapshot.placeholder
    @Published var live2dQueuedAction: PetLive2DQueuedAction?
    @Published var isResting = false
    @Published var live2DClothesIndex = 0

    private var bubbleHideTask: Task<Void, Never>?
    private var animationTime: Double = 0
    private var blinkCountdown = PetCharacterTheme.fallback.motion.randomBlinkInterval()
    private var blinkFramesRemaining = 0
    private var perch: PetPerch = .center

    func apply(state: PetState) {
        self.state = state
        refreshLabels(isMoving: isMoving)
    }

    func updatePerch(_ perch: PetPerch) {
        self.perch = perch
        refreshLabels(isMoving: isMoving)
    }

    func updateCharacter(_ character: PetCharacterTheme) {
        self.character = character
        isResting = false
        live2DClothesIndex = 0
        blinkCountdown = character.motion.randomBlinkInterval()
        refreshLabels(isMoving: isMoving)
    }

    func setResting(_ resting: Bool) {
        isResting = resting
        refreshLabels(isMoving: isMoving && !resting)
    }

    var resolvedLive2DConfiguration: PetLive2DConfiguration? {
        character.live2d?.resolved(forClothesIndex: live2DClothesIndex)
    }

    var live2DWardrobeCount: Int {
        character.live2d?.wardrobeCount ?? 0
    }

    var canCycleLive2DClothes: Bool {
        live2DWardrobeCount > 1
    }

    func showBubble(_ text: String, autoHideMs: Int? = 1800) {
        bubbleHideTask?.cancel()
        bubbleText = text

        guard let autoHideMs, autoHideMs > 0 else { return }
        bubbleHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(autoHideMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.bubbleText = nil
        }
    }

    func updateConnection(connected: Bool) {
        isConnected = connected
        connectionLabel = connected ? "已连接" : "离线"
        refreshLabels(isMoving: isMoving)
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            interactionPulse = 1
            isMoving = false
        }
        refreshLabels(isMoving: isMoving && !dragging)
    }

    func markInteraction() {
        interactionPulse = 1
        haloPulse = 0
    }

    func triggerEdgeBounce() {
        interactionPulse = 1
    }

    func advanceFrame(isMoving: Bool) {
        self.isMoving = isMoving
        let motion = character.motion

        animationTime += isDragging ? 0.12 : (isMoving ? 0.2 : 0.09)
        footPhase += isMoving ? 0.38 : 0.12

        let bobAmplitude: CGFloat = (isDragging ? 3.5 : (isMoving ? 7.5 : 2.8)) * CGFloat(motion.bobAmplitudeMultiplier)
        bodyBob = CGFloat(sin(animationTime * 1.2)) * bobAmplitude

        let stretchAmplitude: CGFloat = (isMoving ? 0.045 : 0.022) * CGFloat(motion.stretchMultiplier)
        bodyStretch = 1 + CGFloat(cos(animationTime * 1.45)) * stretchAmplitude

        let tailAmplitude = (isDragging ? 10.0 : (isMoving ? 24.0 : 13.0)) * motion.tailSwingMultiplier
        tailAngle = sin(animationTime * (isMoving ? 2.2 : 1.35)) * tailAmplitude

        headTilt = sin(animationTime * (isMoving ? 1.9 : 0.9)) * (isDragging ? 7.0 : (isMoving ? 4.4 : 1.6))
        gazeOffset = CGFloat(sin(animationTime * (state == .thinking ? 0.8 : 1.15))) * (state == .thinking ? 3.2 : (isDragging ? 2.1 : 1.6))
        earLift = CGFloat((sin(animationTime * 1.65) + 1) * 0.5) * (state == .thinking ? 7.0 : (isMoving ? 4.5 : 2.5))
        whiskerSwing = sin(animationTime * (isMoving ? 2.3 : 1.2)) * (state == .done ? 9.0 : 5.0)

        switch state {
        case .hidden:
            mouthCurve = 0
        case .idle:
            mouthCurve = isConnected ? 0.28 : -0.08
        case .walking:
            mouthCurve = isConnected ? 0.55 : 0.12
        case .thinking:
            mouthCurve = 0.45
        case .done:
            mouthCurve = 0.92
        }

        haloPulse += isConnected ? 0.08 : 0.035
        moodGlow = (sin(haloPulse) + 1) * 0.5
        interactionPulse = max(0, interactionPulse - (isDragging ? 0.03 : 0.05))

        updateBlink()
        refreshLabels(isMoving: isMoving)
    }

    private func updateBlink() {
        if blinkFramesRemaining > 0 {
            blinkFramesRemaining -= 1
            let phase = Double(blinkFramesRemaining) / 6.0
            eyeOpenScale = max(0.12, CGFloat(phase))
            return
        }

        blinkCountdown -= 1
        eyeOpenScale = 1

        if blinkCountdown <= 0 {
            blinkFramesRemaining = 6
            blinkCountdown = character.motion.randomBlinkInterval()
        }
    }

    private func refreshLabels(isMoving: Bool) {
        if isDragging {
            modeLabel = "拖拽放置"
            return
        }

        if isResting, state != .hidden {
            modeLabel = "休息中"
            return
        }

        switch state {
        case .hidden:
            modeLabel = "已隐藏"
        case .idle:
            modeLabel = isConnected ? perch.restingLabel : "等待连接"
        case .walking:
            if isConnected {
                modeLabel = isMoving ? perch.movingLabel : perch.restingLabel
            } else {
                modeLabel = isMoving ? "离线巡航" : "等待连接"
            }
        case .thinking:
            modeLabel = perch.thinkingLabel
        case .done:
            modeLabel = perch.doneLabel
        }
    }
}

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetCoordinator: NSObject {
    let sceneModel = PetSceneModel()

    private let configuration: LaunchConfiguration
    private let placementStore = PetPlacementStore.shared
    private let characterLibrary = PetCharacterLibrary.shared
    private lazy var ipcClient = PetIPCClient(configuration: configuration, delegate: self)
    private let speechCoordinator = PetSpeechCoordinator()

    private var window: NSWindow?
    private var movementTimer: Timer?
    private var statusItem: NSStatusItem?
    private var companionDiagnosticMenu: NSMenu?
    private var providerSummaryMenu: NSMenu?
    private var characterMenuItems: [NSMenuItem] = []
    private var dragStartMouseLocation: NSPoint?
    private var dragMouseOffset: NSPoint?
    private var ambientDialogueTask: Task<Void, Never>?
    private var tapDispatchTask: Task<Void, Never>?
    private var pendingTapCount = 0

    private var currentX: CGFloat = 0
    private var currentY: CGFloat = 0
    private var anchorX: CGFloat = 0
    private var restY: CGFloat = 0
    private var direction: CGFloat = 1
    private var currentPerch: PetPerch = .center
    private var currentCharacter: PetCharacterTheme
    private var strollFramesRemaining = 0
    private var pauseFramesRemaining = 0
    private var lastVisibleState: PetState = .walking
    private var providerOverviewFingerprint: String?
    private var latestProviderOverview: CompanionProviderOverviewPayload?
    private var lastProviderOverviewAt: Date?
    private var lastConnectionReason: String?
    private var currentEndpointLabel: String
    private var hasConnectedOnce = false
    private var live2dActionSequence = 0

    private var isPointerInteractionActive: Bool {
        dragStartMouseLocation != nil || pendingTapCount > 0 || tapDispatchTask != nil
    }

    private var currentPetSize: NSSize {
        if currentCharacter.rendererKind == .live2d, let live2d = currentCharacter.live2d {
            let size = live2d.resolvedSceneFrameSize
            return NSSize(width: size.width, height: size.height)
        }

        return NSSize(width: 260, height: 228)
    }

    init(configuration: LaunchConfiguration) {
        self.configuration = configuration
        self.currentCharacter = PetCharacterLibrary.shared.selectedCharacter()
        self.currentEndpointLabel = configuration.endpoint?.absoluteString ?? "未配置"
        super.init()
        sceneModel.updateCharacter(currentCharacter)
        refreshDiagnosticPresentation()
    }

    func start() {
        setupWindow()
        setupStatusItem()
        startMovementLoop()
        startAmbientDialogueLoop()
        resetPatrolCycle()
        ipcClient.connect()
        refreshDiagnosticPresentation()
        sceneModel.showBubble("轻点打开 Lime，双击听青柠一句话，三击拿下一步建议", autoHideMs: 2200)
    }

    func stop() {
        movementTimer?.invalidate()
        movementTimer = nil
        ambientDialogueTask?.cancel()
        cancelPendingTapResolution()
        if let screen = window?.screen ?? NSScreen.main {
            persistPlacement(on: screen)
        }
        ipcClient.disconnect()
    }

    @objc private func reconnectIPC() {
        ipcClient.reconnect()
    }

    @objc private func togglePetVisibility() {
        if sceneModel.state == .hidden {
            revealLastVisibleState()
        } else {
            applySceneState(.hidden)
        }
        updateWindowVisibility()
    }

    @objc private func recenterPet() {
        moveToPresetPerch(.center, message: "回到舞台中央啦")
    }

    @objc private func dockLeft() {
        moveToPresetPerch(.left, message: PetPerch.left.placementBubble)
    }

    @objc private func dockCenter() {
        moveToPresetPerch(.center, message: PetPerch.center.placementBubble)
    }

    @objc private func dockRight() {
        moveToPresetPerch(.right, message: PetPerch.right.placementBubble)
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let characterId = sender.representedObject as? String else {
            return
        }

        selectCharacter(id: characterId, announce: true)
    }

    @objc private func promptConversationMenuAction() {
        promptConversation(source: "menu")
    }

    @objc private func promptVoiceConversationMenuAction() {
        requestVoiceConversation(source: "menu")
    }

    @objc private func resetConversationMenuAction() {
        requestChatReset(source: "menu")
    }

    private func toggleRestMode() {
        guard sceneModel.state != .hidden else { return }

        let nextValue = !sceneModel.isResting
        sceneModel.setResting(nextValue)
        sceneModel.markInteraction()
        resetPatrolCycle(startPaused: true)

        if nextValue {
            sceneModel.showBubble("我先休息一会，点月亮就回来", autoHideMs: 1500)
        } else {
            sceneModel.showBubble("我回来继续陪你啦", autoHideMs: 1200)
            queueLive2DStateAction(for: sceneModel.state)
        }
    }

    private func cycleToNextLive2DCharacter() {
        let live2DCharacters = characterLibrary.characters.filter { $0.rendererKind == .live2d }
        guard !live2DCharacters.isEmpty else {
            sceneModel.showBubble("当前还没有可切换的 Live2D 模型", autoHideMs: 1500)
            return
        }

        let currentIndex = live2DCharacters.firstIndex(where: { $0.id == currentCharacter.id }) ?? -1
        let nextIndex = (currentIndex + 1 + live2DCharacters.count) % live2DCharacters.count
        applyCharacter(live2DCharacters[nextIndex], announce: true)
    }

    private func cycleCurrentModelClothes() {
        guard currentCharacter.rendererKind == .live2d, let live2d = currentCharacter.live2d else {
            sceneModel.showBubble("当前不是 Live2D 模型", autoHideMs: 1400)
            return
        }

        let wardrobeCount = live2d.wardrobeCount
        guard wardrobeCount > 1 else {
            sceneModel.showBubble("该模型暂无可切换衣装", autoHideMs: 1500)
            return
        }

        sceneModel.live2DClothesIndex = (sceneModel.live2DClothesIndex + 1) % wardrobeCount
        sceneModel.markInteraction()
        sceneModel.showBubble(
            "切换到 \(currentCharacter.displayName) 衣装 \(sceneModel.live2DClothesIndex + 1)/\(wardrobeCount)",
            autoHideMs: 1400
        )
        queueLive2DStateAction(for: sceneModel.state)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func handleMovementTimer(_ timer: Timer) {
        tick()
    }

    private func applyCharacter(_ character: PetCharacterTheme, announce: Bool) {
        currentCharacter = character
        sceneModel.updateCharacter(character)
        sceneModel.live2dQueuedAction = nil
        updateWindowSizeForCurrentCharacter()
        startAmbientDialogueLoop()
        refreshCharacterMenuState()
        updateStatusButtonIcon()
        queueLive2DStateAction(for: sceneModel.state)

        if announce {
            sceneModel.markInteraction()
            sceneModel.showBubble(character.switchBubble, autoHideMs: 1300)
        }
    }

    private func selectCharacter(id: String, announce: Bool) {
        guard let character = characterLibrary.selectCharacter(id: id) else {
            return
        }

        applyCharacter(character, announce: announce)
    }

    private func refreshCharacterMenuState() {
        for item in characterMenuItems {
            let isSelected = (item.representedObject as? String) == currentCharacter.id
            item.state = isSelected ? .on : .off
        }
    }

    private func updateStatusButtonIcon() {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(
            systemSymbolName: currentCharacter.symbols.menuBar,
            accessibilityDescription: currentCharacter.displayName
        )
        button.toolTip = "Lime Pet · \(currentCharacter.displayName)"
    }

    private func setupWindow() {
        guard let screen = preferredLaunchScreen() else { return }

        let frame = initialFrame(on: screen)
        let window = PetWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = configuration.debugWindowSurface
        window.backgroundColor = configuration.debugWindowSurface
            ? NSColor.systemPink.withAlphaComponent(0.45)
            : .clear
        window.level = .statusBar
        window.hasShadow = configuration.debugWindowSurface
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false

        let rootView = PetView(
            sceneModel: sceneModel,
            availableCharacters: characterLibrary.characters,
            debugWindowSurface: configuration.debugWindowSurface,
            onDragChanged: { [weak self] value in
                self?.handleDragChanged(value)
            },
            onDragEnded: { [weak self] value in
                self?.handleDragEnded(value)
            },
            onCharacterSelected: { [weak self] characterID in
                self?.selectCharacter(id: characterID, announce: true)
            },
            onChatRequested: { [weak self] in
                self?.promptConversation(source: "context_menu")
            },
            onVoiceChatRequested: { [weak self] in
                self?.requestVoiceConversation(source: "context_menu")
            },
            onChatResetRequested: { [weak self] in
                self?.requestChatReset(source: "context_menu")
            },
            onOpenProviderSettingsRequested: { [weak self] in
                self?.requestOpenProviderSettings(source: "context_menu")
            },
            onSyncProviderOverviewRequested: { [weak self] in
                self?.requestProviderOverviewSync(source: "context_menu")
            },
            onReconnectRequested: { [weak self] in
                self?.reconnectIPC()
            },
            onToggleRestRequested: { [weak self] in
                self?.toggleRestMode()
            },
            onCycleClothesRequested: { [weak self] in
                self?.cycleCurrentModelClothes()
            },
            onCycleCharacterRequested: { [weak self] in
                self?.cycleToNextLive2DCharacter()
            },
            onHideRequested: { [weak self] in
                self?.hidePet()
            },
            onQuitRequested: { [weak self] in
                self?.quit()
            }
        )

        let petSize = currentPetSize
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: petSize)
        hostingController.view.autoresizingMask = [.width, .height]
        window.contentViewController = hostingController
        window.setContentSize(petSize)
        window.orderFrontRegardless()
        self.window = window
    }

    private func preferredLaunchScreen() -> NSScreen? {
        if let mainScreen = NSScreen.main {
            return mainScreen
        }
        if let pointerScreen = screen(containing: NSEvent.mouseLocation) {
            return pointerScreen
        }
        return NSScreen.screens.first
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        updateStatusButtonIcon()

        let menu = NSMenu()

        let chatItem = NSMenuItem(title: "和我说话…", action: #selector(promptConversationMenuAction), keyEquivalent: "t")
        chatItem.target = self
        menu.addItem(chatItem)

        let voiceChatItem = NSMenuItem(title: "语音和我说话", action: #selector(promptVoiceConversationMenuAction), keyEquivalent: "v")
        voiceChatItem.target = self
        menu.addItem(voiceChatItem)

        let resetChatItem = NSMenuItem(title: "清空聊天记忆", action: #selector(resetConversationMenuAction), keyEquivalent: "k")
        resetChatItem.target = self
        menu.addItem(resetChatItem)

        menu.addItem(NSMenuItem.separator())

        let reconnectItem = NSMenuItem(title: "重连 Lime", action: #selector(reconnectIPC), keyEquivalent: "r")
        reconnectItem.target = self
        menu.addItem(reconnectItem)

        let providerSettingsItem = NSMenuItem(title: "打开 AI 服务商设置", action: #selector(openProviderSettings), keyEquivalent: "p")
        providerSettingsItem.target = self
        menu.addItem(providerSettingsItem)

        let syncProviderItem = NSMenuItem(title: "立即同步到桌宠", action: #selector(syncProviderOverview), keyEquivalent: "s")
        syncProviderItem.target = self
        menu.addItem(syncProviderItem)

        let diagnosticItem = NSMenuItem(title: "Lime Companion 诊断", action: nil, keyEquivalent: "")
        let diagnosticMenu = NSMenu(title: "Lime Companion 诊断")
        menu.addItem(diagnosticItem)
        menu.setSubmenu(diagnosticMenu, for: diagnosticItem)
        companionDiagnosticMenu = diagnosticMenu

        let providerSummaryItem = NSMenuItem(title: "服务商摘要", action: nil, keyEquivalent: "")
        let providerSummaryMenu = NSMenu(title: "服务商摘要")
        menu.addItem(providerSummaryItem)
        menu.setSubmenu(providerSummaryMenu, for: providerSummaryItem)
        self.providerSummaryMenu = providerSummaryMenu

        let recenterItem = NSMenuItem(title: "回到屏幕中央", action: #selector(recenterPet), keyEquivalent: "c")
        recenterItem.target = self
        menu.addItem(recenterItem)

        let appearanceItem = NSMenuItem(title: "切换外观", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "切换外观")
        for character in characterLibrary.characters {
            let item = NSMenuItem(title: character.displayName, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = character.id
            item.image = NSImage(
                systemSymbolName: character.symbols.menuBar,
                accessibilityDescription: character.displayName
            )
            appearanceMenu.addItem(item)
            characterMenuItems.append(item)
        }
        menu.addItem(appearanceItem)
        menu.setSubmenu(appearanceMenu, for: appearanceItem)

        menu.addItem(NSMenuItem.separator())

        let dockLeftItem = NSMenuItem(title: "停靠左侧", action: #selector(dockLeft), keyEquivalent: "1")
        dockLeftItem.target = self
        menu.addItem(dockLeftItem)

        let dockCenterItem = NSMenuItem(title: "停靠中间", action: #selector(dockCenter), keyEquivalent: "2")
        dockCenterItem.target = self
        menu.addItem(dockCenterItem)

        let dockRightItem = NSMenuItem(title: "停靠右侧", action: #selector(dockRight), keyEquivalent: "3")
        dockRightItem.target = self
        menu.addItem(dockRightItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "显示 / 隐藏桌宠", action: #selector(togglePetVisibility), keyEquivalent: "h")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Lime Pet", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshCharacterMenuState()
        refreshDiagnosticPresentation()
        statusItem.menu = menu
    }

    private func startMovementLoop() {
        movementTimer?.invalidate()
        movementTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(handleMovementTimer(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    private func startAmbientDialogueLoop() {
        ambientDialogueTask?.cancel()
        ambientDialogueTask = Task { [weak self] in
            while !Task.isCancelled {
                let delayNanoseconds = self?.currentCharacter.motion.randomAmbientDelayNanoseconds() ?? 13_000_000_000
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.emitAmbientBubbleIfNeeded()
                }
            }
        }
    }

    private func initialFrame(on screen: NSScreen) -> NSRect {
        let petSize = currentPetSize
        restorePlacement(on: screen)
        restY = floorY(for: screen)
        currentY = restY
        return NSRect(x: currentX, y: currentY, width: petSize.width, height: petSize.height)
    }

    private func restorePlacement(on screen: NSScreen) {
        let petSize = currentPetSize
        if let restored = placementStore.restoreOriginX(on: screen, petSize: petSize) {
            currentPerch = restored.perch
            anchorX = restored.originX
        } else {
            currentPerch = .center
            anchorX = PetPerch.presetOriginX(on: screen, petSize: petSize, perch: .center)
        }

        currentX = anchorX
        direction = currentPerch == .right ? -1 : 1
        sceneModel.updatePerch(currentPerch)
    }

    private func floorY(for screen: NSScreen) -> CGFloat {
        screen.visibleFrame.minY + 10
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func clampAnchor(on screen: NSScreen) {
        let petSize = currentPetSize
        let visible = screen.visibleFrame
        anchorX = min(max(anchorX, visible.minX + 4), visible.maxX - petSize.width - 4)
    }

    private func clampPosition(on screen: NSScreen) {
        let petSize = currentPetSize
        let visible = screen.visibleFrame
        currentX = min(max(currentX, visible.minX + 4), visible.maxX - petSize.width - 4)
        currentY = min(max(currentY, visible.minY + 6), visible.maxY - petSize.height - 4)
    }

    private func roamingBounds(on screen: NSScreen) -> ClosedRange<CGFloat> {
        let petSize = currentPetSize
        clampAnchor(on: screen)
        let visible = screen.visibleFrame
        let minX = visible.minX + 4
        let maxX = visible.maxX - petSize.width - 4
        let roamRadius = currentPerch.roamingRadius * CGFloat(currentCharacter.motion.roamRadiusMultiplier)
        let lower = max(minX, anchorX - roamRadius)
        let upper = min(maxX, anchorX + roamRadius)
        return lower...max(lower, upper)
    }

    private func resetPatrolCycle(startPaused: Bool = false) {
        strollFramesRemaining = startPaused ? 0 : nextStrollFrameCount()
        pauseFramesRemaining = startPaused ? nextPauseFrameCount() : 0
    }

    private func nextStrollFrameCount() -> Int {
        switch currentPerch {
        case .center:
            return Int.random(in: 160...260)
        case .left, .right:
            return Int.random(in: 90...170)
        }
    }

    private func nextPauseFrameCount() -> Int {
        switch currentPerch {
        case .center:
            return Int.random(in: 32...86)
        case .left, .right:
            return Int.random(in: 58...128)
        }
    }

    private func patrolSpeed() -> CGFloat {
        let multiplier = CGFloat(currentCharacter.motion.walkSpeedMultiplier)
        if !sceneModel.isConnected {
            return (currentPerch == .center ? 1.5 : 1.2) * multiplier
        }
        return (currentPerch == .center ? 2.8 : 1.95) * multiplier
    }

    private func persistPlacement(on screen: NSScreen) {
        let petSize = currentPetSize
        placementStore.save(originX: anchorX, perch: currentPerch, on: screen, petSize: petSize)
    }

    private func moveToPresetPerch(_ perch: PetPerch, message: String) {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let petSize = currentPetSize
        currentPerch = perch
        anchorX = PetPerch.presetOriginX(on: screen, petSize: petSize, perch: perch)
        currentX = anchorX
        restY = floorY(for: screen)
        currentY = restY + 18
        direction = perch == .right ? -1 : 1
        sceneModel.updatePerch(perch)
        sceneModel.markInteraction()
        sceneModel.showBubble(message, autoHideMs: 1200)
        resetPatrolCycle(startPaused: true)
        persistPlacement(on: screen)
        window?.setFrameOrigin(NSPoint(x: currentX, y: currentY))
    }

    private func updateWindowSizeForCurrentCharacter() {
        guard let window, let screen = window.screen ?? NSScreen.main else {
            return
        }

        let petSize = currentPetSize
        window.contentViewController?.view.frame = NSRect(origin: .zero, size: petSize)
        window.setContentSize(petSize)
        restY = floorY(for: screen)
        clampAnchor(on: screen)
        clampPosition(on: screen)
        window.setFrameOrigin(NSPoint(x: currentX, y: currentY))
        persistPlacement(on: screen)
    }

    @objc private func openProviderSettings() {
        requestOpenProviderSettings(source: "status_item")
    }

    @objc private func syncProviderOverview() {
        requestProviderOverviewSync(source: "status_item")
    }

    private func hidePet() {
        applySceneState(.hidden)
        updateWindowVisibility()
    }

    private func applySceneState(_ state: PetState) {
        if state != .hidden {
            lastVisibleState = state
        }
        sceneModel.apply(state: state)
        queueLive2DStateAction(for: state)
    }

    private func queueLive2DStateAction(for state: PetState) {
        queueLive2DAction(currentCharacter.live2d?.resolvedStateAction(for: state))
    }

    private func queueLive2DTapAction(_ kind: PetLive2DTapKind) {
        guard let live2d = currentCharacter.live2d, currentCharacter.rendererKind == .live2d else {
            return
        }

        let motion: PetLive2DMotion?
        switch kind {
        case .single:
            motion = live2d.tapActions.single
        case .double:
            motion = live2d.tapActions.double
        case .triple:
            motion = live2d.tapActions.triple
        }

        queueLive2DAction(
            motion.map {
                PetLive2DResolvedActionContent(expressionIndices: [], motion: $0)
            }
        )
    }

    private func queueIncomingLive2DAction(_ payload: CompanionLive2DActionPayload) {
        guard let live2d = currentCharacter.live2d, currentCharacter.rendererKind == .live2d else {
            return
        }

        let motion: PetLive2DMotion?
        if let motionGroup = payload.motionGroup, let motionIndex = payload.motionIndex {
            motion = PetLive2DMotion(group: motionGroup, index: motionIndex)
        } else {
            motion = nil
        }

        queueLive2DAction(
            live2d.resolvedIncomingAction(
                rawExpressions: payload.expressions,
                emotionTags: payload.emotionTags,
                preferredMotion: motion
            )
        )
    }

    private func queueLive2DAction(_ content: PetLive2DResolvedActionContent?) {
        guard currentCharacter.rendererKind == .live2d, let content, content.hasEffect else {
            return
        }

        live2dActionSequence += 1
        sceneModel.live2dQueuedAction = PetLive2DQueuedAction(id: live2dActionSequence, content: content)
    }

    private func revealLastVisibleState() {
        applySceneState(lastVisibleState == .hidden ? .walking : lastVisibleState)
    }

    private func emitAmbientBubbleIfNeeded() {
        guard sceneModel.state != .hidden else { return }
        guard !sceneModel.isDragging else { return }
        guard sceneModel.bubbleText == nil else { return }

        let preferredLines = currentCharacter.dialogue.lines(for: sceneModel.state, isConnected: sceneModel.isConnected)
        let fallbackLines: [String]
        let fallbackText: String
        switch sceneModel.state {
        case .hidden:
            return
        case .idle:
            fallbackLines = sceneModel.isConnected ? currentPerch.ambientIdleLines : []
            fallbackText = sceneModel.isConnected ? "我就在这里待命" : "我还在等 Lime 连上来"
        case .walking:
            fallbackLines = sceneModel.isConnected ? currentPerch.ambientWalkingLines : []
            fallbackText = sceneModel.isConnected ? "我先去巡一圈" : "离线时我也会在这里等你"
        case .thinking:
            fallbackLines = ["我先在旁边陪它想一会", "有进展我会先冒泡提醒你"]
            fallbackText = "我先陪它想想"
        case .done:
            fallbackLines = ["刚刚那件事已经完成啦", "如果你愿意，我还能继续帮你叫出 Lime"]
            fallbackText = "任务已经完成啦"
        }

        let text = (preferredLines + fallbackLines).randomElement() ?? fallbackText
        sceneModel.showBubble(text, autoHideMs: 1500)
    }

    private func tick() {
        guard let window else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        updateWindowVisibility()
        guard sceneModel.state != .hidden else { return }

        let visible = screen.visibleFrame
        restY = floorY(for: screen)

        var isMoving = false
        let shouldFreezeForPointer = isPointerInteractionActive
        let shouldRest = sceneModel.isResting
        let canPatrol =
            sceneModel.state == .walking &&
            !shouldRest &&
            !sceneModel.isDragging &&
            !shouldFreezeForPointer

        if canPatrol {
            let bounds = roamingBounds(on: screen)

            if pauseFramesRemaining > 0 {
                pauseFramesRemaining -= 1
                currentX += (anchorX - currentX) * 0.04
                if pauseFramesRemaining == 0 {
                    strollFramesRemaining = nextStrollFrameCount()
                }
            } else {
                if strollFramesRemaining <= 0 {
                    pauseFramesRemaining = nextPauseFrameCount()
                } else {
                    isMoving = true
                    strollFramesRemaining -= 1
                    currentX += direction * patrolSpeed()

                    if currentX <= bounds.lowerBound {
                        currentX = bounds.lowerBound
                        direction = 1
                        currentY = min(currentY + 14, visible.maxY - currentPetSize.height - 8)
                        sceneModel.triggerEdgeBounce()
                        resetPatrolCycle(startPaused: true)
                    } else if currentX >= bounds.upperBound {
                        currentX = bounds.upperBound
                        direction = -1
                        currentY = min(currentY + 14, visible.maxY - currentPetSize.height - 8)
                        sceneModel.triggerEdgeBounce()
                        resetPatrolCycle(startPaused: true)
                    } else if strollFramesRemaining == 0 {
                        pauseFramesRemaining = nextPauseFrameCount()
                    }
                }
            }

            sceneModel.isFacingRight = direction > 0
        } else if !shouldFreezeForPointer && !shouldRest {
            currentX += (anchorX - currentX) * 0.08
        }

        sceneModel.advanceFrame(isMoving: isMoving)

        if !sceneModel.isDragging && !shouldFreezeForPointer {
            currentY += (restY - currentY) * 0.18
        }

        clampPosition(on: screen)
        window.setFrameOrigin(NSPoint(x: currentX, y: currentY))
    }

    private func updateWindowVisibility() {
        guard let window else { return }
        if sceneModel.state == .hidden {
            window.orderOut(nil)
        } else if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard let window else { return }
        let mouseLocation = NSEvent.mouseLocation

        if dragStartMouseLocation == nil {
            dragStartMouseLocation = mouseLocation
            dragMouseOffset = NSPoint(
                x: mouseLocation.x - window.frame.origin.x,
                y: mouseLocation.y - window.frame.origin.y
            )
            resetPatrolCycle(startPaused: true)
        }

        guard let dragStartMouseLocation else { return }
        let distance = hypot(
            mouseLocation.x - dragStartMouseLocation.x,
            mouseLocation.y - dragStartMouseLocation.y
        )
        if distance < petTapThreshold {
            return
        }

        if !sceneModel.isDragging {
            cancelPendingTapResolution()
            sceneModel.setDragging(true)
            sceneModel.showBubble("把我放到喜欢的位置", autoHideMs: 1000)
        }

        guard let dragMouseOffset else { return }
        currentX = mouseLocation.x - dragMouseOffset.x
        currentY = mouseLocation.y - dragMouseOffset.y

        if let targetScreen = screen(containing: mouseLocation) ?? window.screen ?? NSScreen.main {
            clampPosition(on: targetScreen)
        }

        window.setFrameOrigin(NSPoint(x: currentX, y: currentY))
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let mouseLocation = NSEvent.mouseLocation
        let distance: CGFloat
        if let dragStartMouseLocation {
            distance = hypot(
                mouseLocation.x - dragStartMouseLocation.x,
                mouseLocation.y - dragStartMouseLocation.y
            )
        } else {
            distance = hypot(value.translation.width, value.translation.height)
        }
        dragStartMouseLocation = nil
        dragMouseOffset = nil

        if distance < petTapThreshold {
            registerTapGesture()
            return
        }

        sceneModel.setDragging(false)
        sceneModel.markInteraction()

        guard let screen = screen(containing: mouseLocation) ?? window?.screen ?? NSScreen.main else { return }
        clampPosition(on: screen)
        restY = floorY(for: screen)
        currentPerch = PetPerch.infer(originX: currentX, on: screen, petSize: currentPetSize)
        anchorX = currentX
        currentY = max(currentY, restY + 16)
        direction = currentPerch == .right ? -1 : 1
        sceneModel.updatePerch(currentPerch)
        resetPatrolCycle(startPaused: true)
        persistPlacement(on: screen)
        sceneModel.showBubble(currentPerch.placementBubble, autoHideMs: 1300)
    }

    private func cancelPendingTapResolution() {
        pendingTapCount = 0
        tapDispatchTask?.cancel()
        tapDispatchTask = nil
    }

    private func registerTapGesture() {
        pendingTapCount = min(pendingTapCount + 1, 3)
        tapDispatchTask?.cancel()
        tapDispatchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dispatchAccumulatedTapGesture()
            }
        }
    }

    private func dispatchAccumulatedTapGesture() {
        let tapCount = pendingTapCount
        cancelPendingTapResolution()

        switch tapCount {
        case 3...:
            handleTripleTap()
        case 2:
            handleDoubleTap()
        default:
            handleSingleTap()
        }
    }

    private func handleSingleTap() {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()
        queueLive2DTapAction(.single)

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("正在唤起 Lime…", autoHideMs: 1200)
        resetPatrolCycle(startPaused: true)
        ipcClient.sendTapEvents()
    }

    private func handleDoubleTap() {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()
        queueLive2DTapAction(.double)

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("青柠想一句鼓励给你…", autoHideMs: 1400)
        resetPatrolCycle(startPaused: true)
        ipcClient.requestPetCheer(source: "double_tap")
    }

    private func handleTripleTap() {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()
        queueLive2DTapAction(.triple)

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("青柠在想你的下一步…", autoHideMs: 1400)
        resetPatrolCycle(startPaused: true)
        ipcClient.requestPetNextStep(source: "triple_tap")
    }

    private func promptConversation(source: String) {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()

        guard let text = PetConversationPrompt.present(characterDisplayName: currentCharacter.displayName) else {
            return
        }

        requestChatReply(text: text, source: source)
    }

    private func requestChatReply(text: String, source: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            sceneModel.showBubble("你先跟我说一句话吧", autoHideMs: 1400)
            return
        }

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("我来想想怎么回答你…", autoHideMs: 1500)
        resetPatrolCycle(startPaused: true)
        ipcClient.requestChatReply(text: normalizedText, source: source)
    }

    private func requestChatReset(source: String) {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("好呀，我们从这句重新开始聊", autoHideMs: 1500)
        resetPatrolCycle(startPaused: true)
        ipcClient.requestChatReset(source: source)
    }

    private func requestVoiceConversation(source: String) {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("你说吧，我在认真听", autoHideMs: 1600)
        resetPatrolCycle(startPaused: true)
        ipcClient.requestVoiceChat(source: source)
    }

    private func requestOpenProviderSettings(source: String) {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("正在打开 AI 服务商设置…", autoHideMs: 1200)
        resetPatrolCycle(startPaused: true)
        ipcClient.openProviderSettings(source: source)
    }

    private func requestProviderOverviewSync(source: String) {
        sceneModel.setDragging(false)
        sceneModel.markInteraction()

        guard sceneModel.isConnected else {
            sceneModel.showBubble("Lime 还没连上，我先等它", autoHideMs: 1400)
            ipcClient.reconnect()
            return
        }

        sceneModel.showBubble("正在请求同步桌宠摘要…", autoHideMs: 1200)
        resetPatrolCycle(startPaused: true)
        ipcClient.requestProviderOverviewSync(source: source)
    }

    private func handleProviderOverview(_ overview: CompanionProviderOverviewPayload) {
        latestProviderOverview = overview
        lastProviderOverviewAt = Date()
        let nextFingerprint = providerOverviewFingerprint(for: overview)
        let shouldUpdateBubble = nextFingerprint != providerOverviewFingerprint
        providerOverviewFingerprint = nextFingerprint
        refreshDiagnosticPresentation()

        guard shouldUpdateBubble else { return }

        let shouldInterruptCurrentBubble =
            overview.totalProviderCount == 0 ||
            overview.availableProviderCount == 0 ||
            overview.needsAttentionProviderCount > 0

        guard sceneModel.bubbleText == nil || shouldInterruptCurrentBubble else {
            return
        }

        sceneModel.showBubble(
            petProviderOverviewBubbleText(for: overview),
            autoHideMs: shouldInterruptCurrentBubble ? 2100 : 1500
        )
    }

    private func providerOverviewFingerprint(for overview: CompanionProviderOverviewPayload) -> String {
        let providerSegments = overview.providers.map { provider in
            "\(provider.providerType):\(provider.healthyCount)/\(provider.totalCount):\(provider.available ? 1 : 0):\(provider.needsAttention ? 1 : 0)"
        }
        return (
            [
                String(overview.totalProviderCount),
                String(overview.availableProviderCount),
                String(overview.needsAttentionProviderCount)
            ] + providerSegments
        ).joined(separator: "|")
    }

    private func refreshDiagnosticPresentation() {
        let snapshot = makePetCompanionDiagnosticSnapshot(
            input: PetCompanionDiagnosticInput(
                endpointConfigured: configuration.endpoint != nil,
                endpointLabel: currentEndpointLabel,
                isConnected: sceneModel.isConnected,
                lastConnectionReason: lastConnectionReason,
                hasConnectedOnce: hasConnectedOnce,
                latestProviderOverview: latestProviderOverview,
                lastProviderOverviewAt: lastProviderOverviewAt
            )
        )
        sceneModel.companionDiagnostic = snapshot
        reloadCompanionDiagnosticMenu(with: snapshot)
        reloadProviderSummaryMenu(with: snapshot)
    }

    private func reloadCompanionDiagnosticMenu(with snapshot: PetCompanionDiagnosticSnapshot) {
        guard let companionDiagnosticMenu else { return }
        companionDiagnosticMenu.removeAllItems()
        addReadonlyMenuItem(snapshot.connectionLine, to: companionDiagnosticMenu)
        addReadonlyMenuItem(snapshot.endpointLine, to: companionDiagnosticMenu)
        addReadonlyMenuItem(snapshot.syncLine, to: companionDiagnosticMenu)
        addReadonlyMenuItem(snapshot.lastSyncLine, to: companionDiagnosticMenu)
        addReadonlyMenuItem(snapshot.actionLine, to: companionDiagnosticMenu)
        companionDiagnosticMenu.addItem(.separator())
        snapshot.checkLines.forEach { line in
            addReadonlyMenuItem(line, to: companionDiagnosticMenu)
        }
    }

    private func reloadProviderSummaryMenu(with snapshot: PetCompanionDiagnosticSnapshot) {
        guard let providerSummaryMenu else { return }
        providerSummaryMenu.removeAllItems()
        snapshot.providerLines.forEach { line in
            addReadonlyMenuItem(line, to: providerSummaryMenu)
        }
    }

    private func addReadonlyMenuItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}

extension PetCoordinator: PetIPCClientDelegate {
    func petIPCClient(_ client: PetIPCClient, didChange status: PetIPCConnectionStatus) {
        switch status {
        case .connected(let endpoint):
            currentEndpointLabel = endpoint
            lastConnectionReason = nil
            hasConnectedOnce = true
            sceneModel.updateConnection(connected: true)
            if sceneModel.bubbleText == nil {
                sceneModel.showBubble("已连接到 Lime", autoHideMs: 1400)
            }
        case .disconnected(let reason):
            lastConnectionReason = reason
            sceneModel.updateConnection(connected: false)
            applySceneState(.idle)
            if sceneModel.bubbleText == nil {
                sceneModel.showBubble(reason, autoHideMs: 1400)
            }
        }
        refreshDiagnosticPresentation()
    }

    func petIPCClient(_ client: PetIPCClient, didReceive command: IncomingCommand) {
        switch command {
        case .show:
            revealLastVisibleState()
            updateWindowVisibility()
        case .hide:
            applySceneState(.hidden)
            updateWindowVisibility()
        case .stateChanged(let state):
            applySceneState(state)
            if state == .thinking {
                sceneModel.showBubble("Lime 正在思考…", autoHideMs: 1100)
            } else if state == .done {
                sceneModel.showBubble("任务完成啦", autoHideMs: 1200)
            }
            updateWindowVisibility()
        case .showBubble(let text, let autoHideMs):
            sceneModel.showBubble(text, autoHideMs: autoHideMs)
            if sceneModel.state != .hidden, (autoHideMs ?? 0) >= 2200 {
                speechCoordinator.speak(text)
            }
        case .openChatAnchor:
            sceneModel.showBubble("点我打开 Lime 对话", autoHideMs: 1600)
        case .providerOverview(let overview):
            handleProviderOverview(overview)
        case .live2dAction(let payload):
            queueIncomingLive2DAction(payload)
        }
    }
}
