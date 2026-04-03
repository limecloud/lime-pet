import SwiftUI

struct PetView: View {
    @ObservedObject var sceneModel: PetSceneModel
    let availableCharacters: [PetCharacterTheme]
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
    let onHideRequested: () -> Void
    let onQuitRequested: () -> Void

    private var palette: PetRenderPalette {
        sceneModel.character.palette(for: sceneModel.state)
    }

    private var renderSurfaceTopSpacing: CGFloat {
        sceneModel.character.rendererKind == .live2d ? 10 : 62
    }

    private var sceneFrameSize: CGSize {
        if sceneModel.character.rendererKind == .live2d {
            return CGSize(width: 320, height: 320)
        }

        return CGSize(width: 260, height: 228)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if debugWindowSurface {
                debugSurface
            }

            if let bubbleText = sceneModel.bubbleText {
                bubble(text: bubbleText)
                    .offset(x: sceneModel.isFacingRight ? 24 : -24, y: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            ambientGlow

            VStack(spacing: 0) {
                Spacer(minLength: renderSurfaceTopSpacing)
                PetRenderSurface(sceneModel: sceneModel, palette: palette)
            }

            if sceneModel.isDragging {
                dragGuide
                    .offset(y: 160)
            }
        }
        .frame(width: sceneFrameSize.width, height: sceneFrameSize.height)
        .contentShape(Rectangle())
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
                ForEach(availableCharacters, id: \.id) { character in
                    Button(character.displayName) {
                        onCharacterSelected(character.id)
                    }
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

    private func bubble(text: String) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.21))
                .lineLimit(2)
                .minimumScaleFactor(0.92)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.88), lineWidth: 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(palette.glow.opacity(0.34), lineWidth: 1.2)
                )
                .shadow(color: Color.white.opacity(0.24), radius: 8, y: -1)

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
