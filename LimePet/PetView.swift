import SwiftUI

struct PetView: View {
    @ObservedObject var sceneModel: PetSceneModel
    let debugWindowSurface: Bool
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onCharacterSelected: (String) -> Void
    let onChatRequested: () -> Void
    let onVoiceChatRequested: () -> Void
    let onChatResetRequested: () -> Void
    let onOpenProviderSettingsRequested: () -> Void
    let onSyncProviderOverviewRequested: () -> Void
    let onReconnectRequested: () -> Void
    let onToggleRestRequested: () -> Void
    let onInstallModelRequested: () -> Void
    let onCycleClothesRequested: () -> Void
    let onCycleCharacterRequested: () -> Void
    let onHideRequested: () -> Void
    let onQuitRequested: () -> Void
    @State private var isHoveringLive2DChrome = false

    private var palette: PetRenderPalette {
        sceneModel.character.palette(for: sceneModel.state)
    }

    private var live2DConfiguration: PetLive2DConfiguration? {
        sceneModel.resolvedLive2DConfiguration
    }

    private var sceneFrameSize: CGSize {
        if sceneModel.character.rendererKind == .live2d,
           let configuration = live2DConfiguration ?? sceneModel.character.live2d {
            return configuration.resolvedSceneFrameSize
        }

        return CGSize(width: 260, height: 228)
    }

    private var showsLive2DChrome: Bool {
        sceneModel.character.rendererKind == .live2d
    }

    private var showsChromeOverlay: Bool {
        showsLive2DChrome && isHoveringLive2DChrome
    }

    private var showsLive2DStatusCard: Bool {
        if !showsLive2DChrome {
            return false
        }

        if sceneModel.isResting {
            return false
        }

        switch sceneModel.currentInstallState {
        case .installable, .installing, .updateAvailable, .failed:
            return true
        case .bundled, .installed:
            return false
        }
    }

    private var quickMenuTopPadding: CGFloat {
        showsLive2DStatusCard ? 162 : 92
    }

    private var shouldRenderAmbientGlow: Bool {
        sceneModel.character.id == "dewy-lime"
    }

    private var showsInstallShortcut: Bool {
        if sceneModel.currentInstallState.canInstall {
            return true
        }

        if case .installing = sceneModel.currentInstallState {
            return true
        }

        return false
    }

    private var statusTitle: String {
        if sceneModel.isResting {
            return "\(sceneModel.character.displayName) 休息中"
        }

        if sceneModel.character.rendererKind == .live2d {
            switch sceneModel.currentInstallState {
            case .installable:
                return "\(sceneModel.character.displayName) 待安装"
            case .installing:
                return "\(sceneModel.character.displayName) 安装中"
            case .installed:
                return "\(sceneModel.character.displayName) 已安装"
            case .updateAvailable:
                return "\(sceneModel.character.displayName) 可更新"
            case .failed:
                return "\(sceneModel.character.displayName) 安装失败"
            case .bundled:
                return "\(sceneModel.character.displayName) Live2D 舞台"
            }
        }

        return "\(sceneModel.character.displayName) 已待命"
    }

    private var statusMessage: String {
        if sceneModel.isResting {
            return "舞台已收起，点月亮按钮就能继续陪你。"
        }

        if sceneModel.character.rendererKind == .live2d {
            switch sceneModel.currentInstallState {
            case .installable:
                return "当前模型还未安装，移入左侧快捷菜单后点一下安装就能下载到本地。"
            case .installing(let progress):
                return "正在下载并校验模型资源，当前进度 \(Int(progress * 100))%。"
            case .updateAvailable:
                return "本地模型可继续使用，也可以点安装按钮拉取最新版本。"
            case .failed(let message):
                return message
            case .bundled, .installed:
                break
            }

            if sceneModel.canCycleLive2DClothes {
                return "衣装 \(sceneModel.live2DClothesIndex + 1)/\(sceneModel.live2DWardrobeCount)，左侧快捷按钮可休息、换装和切模型。"
            }

            return "当前模型暂无可切换衣装，左侧可休息或切换到下一个模型。"
        }

        return "当前是青橙守望形态，右键还能打开完整上下文菜单。"
    }

    var body: some View {
        ZStack(alignment: .top) {
            if debugWindowSurface {
                debugSurface
            }

            if let bubbleText = sceneModel.bubbleText {
                bubble(text: bubbleText)
                    .offset(
                        x: (showsLive2DChrome ? 92 : 0) + (sceneModel.isFacingRight ? 18 : -18),
                        y: 18
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            ambientGlow

            Group {
                if sceneModel.character.rendererKind == .live2d {
                    ZStack {
                        if sceneModel.canRenderCurrentLive2D {
                            PetRenderSurface(sceneModel: sceneModel, palette: palette)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .opacity(sceneModel.isResting ? 0.08 : 1)
                                .scaleEffect(sceneModel.isResting ? 0.92 : 1, anchor: .bottom)
                        } else {
                            live2DInstallStage
                        }
                    }
                    .offset(
                        x: showsLive2DChrome ? 86 : 0,
                        y: sceneModel.isResting ? 28 : -8
                    )
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 62)
                        PetRenderSurface(sceneModel: sceneModel, palette: palette)
                    }
                }
            }

            if showsLive2DChrome {
                live2DStatusCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 24)
                    .padding(.leading, 26)
                    .opacity(showsChromeOverlay && showsLive2DStatusCard ? 1 : 0)
                    .offset(
                        x: showsChromeOverlay && showsLive2DStatusCard ? 0 : -20,
                        y: showsChromeOverlay && showsLive2DStatusCard ? 0 : 6
                    )
                    .allowsHitTesting(showsChromeOverlay && showsLive2DStatusCard)

                live2DQuickMenu
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, quickMenuTopPadding)
                    .padding(.leading, 26)
                    .opacity(showsChromeOverlay ? 1 : 0)
                    .offset(x: showsChromeOverlay ? 0 : -20, y: showsChromeOverlay ? 0 : 10)
                    .allowsHitTesting(showsChromeOverlay)
            }

            if sceneModel.isDragging {
                dragGuide
                    .offset(y: 160)
            }
        }
        .frame(width: sceneFrameSize.width, height: sceneFrameSize.height)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringLive2DChrome = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onDragChanged(value)
                }
                .onEnded { value in
                    onDragEnded(value)
                }
        )
        .contextMenu {
            Menu("切换桌宠") {
                ForEach(sceneModel.availableCharacters, id: \.id) { character in
                    Button(character.displayName) {
                        onCharacterSelected(character.id)
                    }
                }
            }

            if sceneModel.character.rendererKind == .live2d,
               sceneModel.currentInstallState.canInstall {
                Divider()

                Button("\(sceneModel.currentInstallState.actionTitle)当前模型") {
                    onInstallModelRequested()
                }
            }

            Divider()

            Button("和我说话…") {
                onChatRequested()
            }

            Button("语音和我说话") {
                onVoiceChatRequested()
            }

            Button("清空聊天记忆") {
                onChatResetRequested()
            }

            Divider()

            Menu("Lime Companion 诊断") {
                diagnosticReadonlyItem(sceneModel.companionDiagnostic.connectionLine)
                diagnosticReadonlyItem(sceneModel.companionDiagnostic.endpointLine)
                diagnosticReadonlyItem(sceneModel.companionDiagnostic.syncLine)
                diagnosticReadonlyItem(sceneModel.companionDiagnostic.lastSyncLine)
                diagnosticReadonlyItem(sceneModel.companionDiagnostic.actionLine)
                Divider()
                ForEach(Array(sceneModel.companionDiagnostic.checkLines.enumerated()), id: \.offset) { _, line in
                    diagnosticReadonlyItem(line)
                }
            }

            Menu("服务商摘要") {
                ForEach(Array(sceneModel.companionDiagnostic.providerLines.enumerated()), id: \.offset) { _, line in
                    diagnosticReadonlyItem(line)
                }
            }

            Divider()

            Button("重连 Lime") {
                onReconnectRequested()
            }

            Button("立即同步到桌宠") {
                onSyncProviderOverviewRequested()
            }

            Button("打开 AI 服务商设置") {
                onOpenProviderSettingsRequested()
            }

            Button("隐藏桌宠") {
                onHideRequested()
            }

            Button("退出 Lime Pet", role: .destructive) {
                onQuitRequested()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: sceneModel.bubbleText)
        .animation(.easeInOut(duration: 0.2), value: sceneModel.state)
        .animation(.spring(response: 0.24, dampingFraction: 0.7), value: sceneModel.isDragging)
        .animation(.easeInOut(duration: 0.2), value: sceneModel.character.id)
        .animation(.easeInOut(duration: 0.22), value: sceneModel.isResting)
        .animation(.easeInOut(duration: 0.18), value: showsChromeOverlay)
    }

    private func diagnosticReadonlyItem(_ title: String) -> some View {
        Button(title) {}
            .disabled(true)
    }

    private var debugSurface: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.red.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                )

            Text("DEBUG SURFACE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(14)
        }
    }

    private var live2DStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusPill(text: sceneModel.connectionLabel, accent: false)
                statusPill(text: sceneModel.modeLabel, accent: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.14, green: 0.24, blue: 0.18))

                Text(statusMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(red: 0.31, green: 0.42, blue: 0.35))
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 188, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.94),
                            Color(red: 0.91, green: 0.99, blue: 0.93).opacity(0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
    }

    private func statusPill(text: String, accent: Bool) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(
                accent
                    ? Color.white.opacity(0.96)
                    : Color(red: 0.17, green: 0.28, blue: 0.2)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        accent
                            ? LinearGradient(
                                colors: [
                                    Color(red: 0.47, green: 0.69, blue: 0.54),
                                    Color(red: 0.33, green: 0.56, blue: 0.41)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(0.94),
                                    Color(red: 0.93, green: 0.98, blue: 0.94)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
    }

    private var live2DQuickMenu: some View {
        VStack(spacing: 10) {
            quickActionButton(
                symbol: sceneModel.isResting ? "sun.max.fill" : "moon.stars.fill",
                title: sceneModel.isResting ? "唤醒" : "休息",
                emphasis: sceneModel.isResting ? 1 : 0.96,
                action: onToggleRestRequested
            )

            if showsInstallShortcut {
                quickActionButton(
                    symbol: installButtonSymbol,
                    title: sceneModel.currentInstallState.actionTitle,
                    emphasis: 1,
                    isEnabled: sceneModel.currentInstallState.canInstall,
                    action: onInstallModelRequested
                )
            }

            if sceneModel.canCycleLive2DClothes {
                quickActionButton(
                    symbol: "tshirt.fill",
                    title: "换装",
                    emphasis: 0.96,
                    action: onCycleClothesRequested
                )
            }

            quickActionButton(
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                title: "切换",
                emphasis: 0.96,
                action: onCycleCharacterRequested
            )
        }
    }

    private func quickActionButton(
        symbol: String,
        title: String,
        emphasis: Double,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.18, green: 0.3, blue: 0.22))
            .frame(width: 58, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color(red: 0.88, green: 0.98, blue: 0.9).opacity(0.88)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 7)
            .opacity(isEnabled ? emphasis : 0.72)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var installButtonSymbol: String {
        switch sceneModel.currentInstallState {
        case .installable:
            return "arrow.down.circle.fill"
        case .installing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .updateAvailable:
            return "arrow.clockwise.circle.fill"
        case .failed:
            return "exclamationmark.arrow.circlepath"
        case .bundled, .installed:
            return "arrow.down.circle.fill"
        }
    }

    private var live2DInstallStage: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                Color(red: 0.9, green: 0.98, blue: 0.92).opacity(0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)

                Image(systemName: installButtonSymbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color(red: 0.21, green: 0.42, blue: 0.28))
            }

            VStack(spacing: 8) {
                Text(statusTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.25, blue: 0.19))

                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.31, green: 0.41, blue: 0.34))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if sceneModel.currentInstallState.canInstall {
                Button("\(sceneModel.currentInstallState.actionTitle)到本地") {
                    onInstallModelRequested()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.69, blue: 0.51),
                                    Color(red: 0.32, green: 0.54, blue: 0.39)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bubble(text: String) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.21))
                .lineLimit(2)
                .minimumScaleFactor(0.92)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    Color(red: 0.95, green: 0.99, blue: 0.96).opacity(0.94),
                                    palette.belly.opacity(0.78)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.88), lineWidth: 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.glow.opacity(0.34), lineWidth: 1.2)
                )
                .shadow(color: Color.white.opacity(0.24), radius: 8, y: -1)
                .frame(maxWidth: 230)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(45))
                .frame(maxWidth: .infinity, alignment: sceneModel.isFacingRight ? .trailing : .leading)
                .padding(.horizontal, 22)
                .offset(y: -5)
        }
        .offset(y: CGFloat(sin(sceneModel.haloPulse * 0.92)) * 2.2)
        .shadow(color: palette.glow.opacity(0.14), radius: 14, y: 7)
        .shadow(color: Color.black.opacity(0.16), radius: 18, y: 9)
    }

    private var ambientGlow: some View {
        Group {
            if shouldRenderAmbientGlow {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    palette.glow.opacity(0.1 + sceneModel.moodGlow * 0.08),
                                    palette.shell.opacity(0.04),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 72
                            )
                        )
                        .frame(width: 148, height: 148)
                        .scaleEffect(1 + sceneModel.moodGlow * 0.12 + sceneModel.interactionPulse * 0.08)
                        .offset(y: 110 + sceneModel.bodyBob * 0.12)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    palette.glow.opacity(0.16 + sceneModel.moodGlow * 0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 6,
                                endRadius: 74
                            )
                        )
                        .frame(width: 126, height: 74)
                        .offset(y: 132 + sceneModel.bodyBob * 0.16)

                    if !sceneModel.isDragging {
                        ambientMotes
                            .offset(y: 100 + sceneModel.bodyBob * 0.14)
                    }

                    if sceneModel.isMoving && !sceneModel.isDragging {
                        movementTrail
                            .offset(x: sceneModel.isFacingRight ? -58 : 58, y: 152)
                    }

                    if sceneModel.isDragging {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                            .foregroundStyle(palette.glow.opacity(0.45))
                            .frame(width: 164, height: 132)
                            .offset(y: 114)
                    }
                }
            }
        }
    }

    private var ambientMotes: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.66 - Double(index) * 0.1),
                                palette.glow.opacity(0.18 - Double(index) * 0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: CGFloat(8 - index * 2), height: CGFloat(8 - index * 2))
                    .blur(radius: 0.4)
                    .offset(
                        y: CGFloat(sin(sceneModel.haloPulse * 1.1 + Double(index) * 0.78)) * CGFloat(3 + index)
                    )
            }
        }
        .opacity(0.26 + sceneModel.moodGlow * 0.08)
    }

    @ViewBuilder
    private var movementTrail: some View {
        switch sceneModel.character.accessories.trail {
        case .none:
            EmptyView()
        case .glowDots:
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(palette.glow.opacity(0.14 - Double(index) * 0.03))
                        .frame(width: CGFloat(8 - index * 2), height: CGFloat(8 - index * 2))
                        .offset(y: CGFloat(sin(sceneModel.haloPulse * 1.35 + Double(index) * 0.82)) * CGFloat(2 + index))
                }
            }
        case .sunMotes:
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: CGFloat(9 - index), weight: .bold))
                        .foregroundStyle(palette.glow.opacity(0.22 - Double(index) * 0.04))
                        .rotationEffect(.degrees(Double(index) * 8 + sin(sceneModel.haloPulse * 1.28 + Double(index)) * 12))
                        .offset(y: CGFloat(sin(sceneModel.haloPulse * 1.12 + Double(index) * 0.76)) * CGFloat(2 + index))
                }
            }
        case .sparkles:
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: index == 1 ? "sparkles" : "sparkle")
                        .font(.system(size: CGFloat(9 - index), weight: .semibold))
                        .foregroundStyle(palette.glow.opacity(0.2 - Double(index) * 0.04))
                        .rotationEffect(.degrees(Double(index) * -10 + sin(sceneModel.haloPulse * 1.44 + Double(index) * 0.8) * 10))
                        .offset(y: CGFloat(sin(sceneModel.haloPulse * 1.24 + Double(index) * 0.7)) * CGFloat(3 + index))
                }
            }
        }
    }

    private var dragGuide: some View {
        Text("拖拽放置，松手后我会记住这个停靠点")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(palette.glow.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: palette.glow.opacity(0.12), radius: 10, y: 5)
    }
}
