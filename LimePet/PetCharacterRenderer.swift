import AppKit
import SwiftUI

private let defaultPetArtBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return .main
    #endif
}()

private enum PetSpriteLibrary {
    static let limeSpirit: NSImage? = {
        let candidates = [
            defaultPetArtBundle.url(forResource: "dewy-lime-shadow", withExtension: "png"),
            defaultPetArtBundle.url(forResource: "dewy-lime-shadow", withExtension: "png", subdirectory: "Resources")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }()

    static func image(for characterID: String) -> NSImage? {
        guard characterID == "dewy-lime" || characterID == "lime-scout" else { return nil }
        return limeSpirit
    }
}

private extension Double {
    var cg: CGFloat { CGFloat(self) }
}

private struct PetBodyShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + rect.height * 0.12
        let sideInset = rect.width * 0.06
        let cheek = rect.height * 0.18
        let chin = rect.height * 0.12

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - sideInset, y: top + cornerRadius * 0.4),
            control1: CGPoint(x: rect.midX + rect.width * 0.28, y: rect.minY + 2),
            control2: CGPoint(x: rect.maxX - sideInset * 0.2, y: rect.minY + rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.midY + cheek),
            control1: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.height * 0.24),
            control2: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.04)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - chin),
            control: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY + rect.height * 0.03)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY + cheek),
            control: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY + rect.height * 0.03)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + sideInset, y: top + cornerRadius * 0.4),
            control1: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04),
            control2: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.height * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX + sideInset * 0.2, y: rect.minY + rect.height * 0.04),
            control2: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.minY + 2)
        )
        return path
    }
}

private struct PetEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.34)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.34)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18)
        )
        return path
    }
}

private struct PetTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.20),
            control1: CGPoint(x: rect.width * 0.18, y: rect.minY - rect.height * 0.12),
            control2: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY),
            control1: CGPoint(x: rect.maxX + rect.width * 0.06, y: rect.minY + rect.height * 0.42),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.44, y: rect.maxY + rect.height * 0.02),
            control2: CGPoint(x: rect.width * 0.12, y: rect.maxY - rect.height * 0.04)
        )
        return path
    }
}

private struct PetLeafTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.78, y: rect.minY + rect.height * 0.04),
            control: CGPoint(x: rect.width * 0.34, y: rect.minY - rect.height * 0.3)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.14)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.72, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.width * 0.38, y: rect.maxY + rect.height * 0.16)
        )
        return path
    }
}

private struct PetBellyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.08)
        )
        return path
    }
}

private struct PetScarfTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.08))
        path.closeSubpath()
        return path
    }
}

private struct PetCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.maxY - rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PetPawShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.width * 0.5, style: .continuous).path(in: rect)
    }
}

private struct PetSmile: Shape {
    let curve: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.midY - curve * 2.2
        let control = CGPoint(x: rect.midX, y: rect.midY + curve * rect.height * 0.8)
        path.move(to: CGPoint(x: rect.minX + 2, y: baseline))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 2, y: baseline), control: control)
        return path
    }
}

struct PetCharacterRenderer: View {
    @ObservedObject var sceneModel: PetSceneModel
    let palette: PetRenderPalette

    private var character: PetCharacterTheme {
        sceneModel.character
    }

    private var geometry: PetCharacterGeometry {
        character.geometry
    }

    private var accessories: PetCharacterAccessories {
        character.accessories
    }

    private var bodyWidthScale: CGFloat {
        1 - max(0, sceneModel.bodyStretch - 1) * 0.45
    }

    private var footLiftFront: CGFloat {
        CGFloat(sin(sceneModel.footPhase)) * 8
    }

    private var footLiftBack: CGFloat {
        CGFloat(sin(sceneModel.footPhase + .pi)) * 8
    }

    private var spriteImage: NSImage? {
        PetSpriteLibrary.image(for: character.id)
    }

    private var spriteFloatOffsetY: CGFloat {
        sceneModel.bodyBob * 0.62 + CGFloat(sin(sceneModel.haloPulse * 0.92)) * 2.6 + spriteInteractionLift - 6
    }

    private var spriteBodyScaleX: CGFloat {
        bodyWidthScale * (1 + sceneModel.interactionPulse * 0.04 + spriteLandingCompression * 0.04)
    }

    private var spriteBodyScaleY: CGFloat {
        sceneModel.bodyStretch + sceneModel.interactionPulse * 0.028 - spriteLandingCompression * 0.06 + CGFloat(cos(sceneModel.haloPulse * 0.82)) * 0.012
    }

    private var spriteRotation: Double {
        sceneModel.headTilt * 0.24
            + sin(sceneModel.footPhase * 0.18) * (sceneModel.isMoving ? 1.8 : 0.6)
            + sin(Double(spriteInteractionPhase) * .pi * 1.45) * Double(sceneModel.interactionPulse) * 5.2
    }

    private var spriteGlowOpacity: Double {
        0.16 + sceneModel.moodGlow * 0.16 + Double(sceneModel.interactionPulse) * 0.12
    }

    private var spriteShimmerOffsetX: CGFloat {
        CGFloat(sin(sceneModel.haloPulse * 0.55 + 0.4)) * 20
    }

    private var spriteInteractionPhase: CGFloat {
        1 - sceneModel.interactionPulse
    }

    private var spriteInteractionLift: CGFloat {
        -CGFloat(sin(Double(spriteInteractionPhase) * .pi)) * sceneModel.interactionPulse * 22
    }

    private var spriteLandingCompression: CGFloat {
        CGFloat(sin(Double(spriteInteractionPhase) * .pi * 1.5 + 0.35)) * sceneModel.interactionPulse
    }

    var body: some View {
        Group {
            if let spriteImage {
                rasterSpirit(image: spriteImage)
            } else {
                ZStack {
                    shadow
                    creature
                }
            }
        }
        .frame(width: 156, height: 176)
    }

    private func rasterSpirit(image: NSImage) -> some View {
        let spriteSize: CGFloat = 148

        return ZStack {
            spriteFloorAura
            spriteAura
            spriteHaloRibbon
            spriteInteractionRipple
            spriteAmbientMotes
            spriteStateOrbit

            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: spriteSize, height: spriteSize)
                    .overlay {
                        spriteShimmerMask(image: image, size: spriteSize)
                    }
                    .shadow(color: palette.glow.opacity(0.16 + sceneModel.moodGlow * 0.08), radius: 16, y: 10)
                    .shadow(color: Color.white.opacity(0.1), radius: 6, y: -2)
            }
            .rotationEffect(.degrees(spriteRotation))
            .scaleEffect(x: spriteBodyScaleX, y: spriteBodyScaleY)
            .scaleEffect(
                x: sceneModel.isFacingRight ? CGFloat(1) : CGFloat(-1),
                y: 1
            )
            .saturation(sceneModel.isConnected ? 1.04 : 0.82)
            .brightness(sceneModel.isConnected ? 0.01 : -0.04)
            .offset(y: spriteFloatOffsetY)

            if sceneModel.state == .thinking || sceneModel.state == .done {
                stateAccessory
                    .offset(y: -28)
            }
        }
    }

    private var spriteFloorAura: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.08))
                .frame(width: 80, height: 18)
                .blur(radius: 2)
                .scaleEffect(
                    x: 1.02 + sceneModel.moodGlow * 0.06,
                    y: max(0.84, 1 - sceneModel.bodyBob * 0.008)
                )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.glow.opacity(0.18 + sceneModel.moodGlow * 0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 40
                    )
                )
                .frame(width: 96, height: 30)
                .blur(radius: 10)
                .opacity(0.85 + sceneModel.interactionPulse * 0.12)
        }
        .offset(y: 78 + sceneModel.bodyBob * 0.18)
    }

    private var spriteAura: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.glow.opacity(spriteGlowOpacity),
                            palette.shell.opacity(0.08 + sceneModel.moodGlow * 0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 74
                    )
                )
                .frame(width: 154, height: 154)
                .blur(radius: 10)
                .scaleEffect(1.02 + sceneModel.moodGlow * 0.1 + sceneModel.interactionPulse * 0.06)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            palette.glow.opacity(0.14),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 126, height: 126)
                .blur(radius: 0.3)
                .scaleEffect(1 + sceneModel.moodGlow * 0.06)
                .opacity(0.62)
        }
        .offset(y: spriteFloatOffsetY - 4)
    }

    private var spriteHaloRibbon: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.62)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.clear,
                            palette.glow.opacity(0.12),
                            Color.white.opacity(0.4),
                            palette.glow.opacity(0.16),
                            Color.clear
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                )
                .frame(width: 136, height: 136)
                .rotationEffect(.degrees(sceneModel.haloPulse * 21))

            Circle()
                .trim(from: 0.48, to: 0.86)
                .stroke(
                    LinearGradient(
                        colors: [
                            palette.shell.opacity(0.06),
                            palette.glow.opacity(0.18),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 122, height: 122)
                .rotationEffect(.degrees(-sceneModel.haloPulse * 16))
        }
        .blur(radius: 0.35)
        .opacity(0.42 + sceneModel.moodGlow * 0.12)
        .offset(y: spriteFloatOffsetY - 6)
    }

    private var spriteInteractionRipple: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            palette.glow.opacity(0.22),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 96, height: 96)
                .scaleEffect(0.84 + spriteInteractionPhase * 0.62)
                .opacity(sceneModel.interactionPulse * 0.26)

            Circle()
                .stroke(palette.glow.opacity(0.22), lineWidth: 1)
                .frame(width: 82, height: 82)
                .scaleEffect(1.04 + spriteInteractionPhase * 0.48)
                .opacity(sceneModel.interactionPulse * 0.18)
        }
        .offset(y: spriteFloatOffsetY - 2)
    }

    private var spriteAmbientMotes: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let phase = sceneModel.haloPulse * 0.82 + Double(index) * 1.24
                let x = cos(phase) * (18 + Double(index) * 6)
                let y = sin(phase * 1.18) * (8 + Double(index % 2) * 5) - 34 - Double(index) * 2

                Group {
                    if index.isMultiple(of: 2) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.82),
                                        palette.glow.opacity(0.34)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 8 + CGFloat(index), weight: .semibold))
                            .foregroundStyle(palette.shell.opacity(0.52 + Double(index) * 0.04))
                    }
                }
                .frame(width: 10 + CGFloat(index), height: 10 + CGFloat(index))
                .blur(radius: index.isMultiple(of: 2) ? 0.2 : 0)
                .opacity(0.18 + sceneModel.moodGlow * 0.12 - Double(index) * 0.02)
                .scaleEffect(0.92 + CGFloat(sin(phase * 1.1)) * 0.08)
                .offset(x: x.cg, y: y.cg + spriteFloatOffsetY * 0.18)
            }
        }
    }

    @ViewBuilder
    private var spriteStateOrbit: some View {
        switch sceneModel.state {
        case .thinking:
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = sceneModel.haloPulse * 1.12 + Double(index) * 2.08
                    Image(systemName: index == 1 ? "leaf.fill" : "circle.fill")
                        .font(.system(size: index == 1 ? 9 : 6, weight: .semibold))
                        .foregroundStyle(index == 1 ? palette.shell.opacity(0.72) : Color.white.opacity(0.7 - Double(index) * 0.1))
                        .shadow(color: palette.glow.opacity(0.16), radius: 4, y: 2)
                        .offset(
                            x: CGFloat(cos(phase) * 24),
                            y: CGFloat(sin(phase * 1.08) * 10) - 34 + spriteFloatOffsetY * 0.12
                        )
                }
            }
        case .done:
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    let phase = sceneModel.haloPulse * 1.26 + Double(index) * (.pi / 2)
                    Image(systemName: index.isMultiple(of: 2) ? "sparkles" : "star.fill")
                        .font(.system(size: 8 + CGFloat(index % 2), weight: .bold))
                        .foregroundStyle(Color.white, palette.glow)
                        .shadow(color: palette.glow.opacity(0.2), radius: 6, y: 2)
                        .scaleEffect(0.88 + CGFloat(sin(phase * 1.2)) * 0.12)
                        .offset(
                            x: CGFloat(cos(phase) * 34),
                            y: CGFloat(sin(phase) * 12) - 28 + spriteFloatOffsetY * 0.08
                        )
                }
            }
        default:
            EmptyView()
        }
    }

    private func spriteShimmerMask(image: NSImage, size: CGFloat) -> some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.white.opacity(0.08),
                Color.white.opacity(0.28),
                Color.white.opacity(0.06),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: size * 0.54, height: size * 1.08)
        .rotationEffect(.degrees(18))
        .blur(radius: 10)
        .offset(x: spriteShimmerOffsetX, y: -4)
        .blendMode(.screen)
        .mask {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
        .opacity(0.78)
    }

    private var shadow: some View {
        Ellipse()
            .fill(Color.black.opacity(0.1))
            .frame(width: geometry.shadowWidth.cg * 0.72, height: geometry.shadowHeight.cg * 0.76)
            .blur(radius: 1.2)
            .scaleEffect(1 + sceneModel.interactionPulse * 0.04)
            .offset(y: 90)
    }

    private var creature: some View {
        ZStack {
            tail
            neckAccessory
                .offset(y: 40)
            headCluster
                .offset(y: 6)
            headAccessory
                .offset(y: -56)
            stateAccessory
                .offset(y: -60)
        }
        .offset(y: sceneModel.bodyBob)
        .rotationEffect(.degrees(sceneModel.headTilt * 0.18))
        .scaleEffect(
            x: (sceneModel.isFacingRight ? CGFloat(1) : CGFloat(-1)) * bodyWidthScale,
            y: sceneModel.bodyStretch
        )
        .saturation(sceneModel.isConnected ? 1 : 0.78)
        .brightness(sceneModel.isConnected ? 0 : -0.04)
    }

    private var headWidth: CGFloat {
        geometry.headWidth.cg * 0.74
    }

    private var headHeight: CGFloat {
        geometry.headHeight.cg * 0.78
    }

    private var torsoWidth: CGFloat {
        geometry.headWidth.cg * 0.76
    }

    private var torsoHeight: CGFloat {
        geometry.headHeight.cg * 0.48
    }

    private var muzzleWidth: CGFloat {
        geometry.bellyWidth.cg * 0.72
    }

    private var muzzleHeight: CGFloat {
        geometry.bellyHeight.cg * 0.32
    }

    private var eyeOpenAmount: CGFloat {
        sceneModel.isConnected
            ? sceneModel.eyeOpenScale
            : max(0.68, sceneModel.eyeOpenScale * 0.86)
    }

    private var tail: some View {
        PetLeafTailShape()
            .fill(
                LinearGradient(
                    colors: [
                        palette.accent.opacity(0.9),
                        palette.shell.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                    )
            )
            .overlay(
                PetLeafTailShape()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .frame(width: geometry.tailWidth.cg * 0.56, height: geometry.tailHeight.cg * 0.8)
            .rotationEffect(.degrees(-18 + sceneModel.tailAngle * 0.48), anchor: .trailing)
            .opacity(0.92)
            .offset(x: -30, y: 40 + sceneModel.bodyBob * 0.08)
    }

    private var headCluster: some View {
        ZStack {
            backEar
            frontEar

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            palette.shell.opacity(0.99),
                            palette.shell.opacity(0.9)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: headWidth, height: headHeight)
                .overlay(
                    Ellipse()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1.1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.glow.opacity(0.22 + sceneModel.moodGlow * 0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: headWidth * 0.7
                    )
                )
                .frame(width: headWidth * 1.18, height: headHeight * 1.18)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(width: headWidth * 0.14, height: headHeight * 0.42)
                .offset(x: headWidth * 0.06, y: -headHeight * 0.18)

            Ellipse()
                .fill(palette.belly.opacity(0.97))
                .frame(width: headWidth * 0.56, height: headHeight * 0.44)
                .overlay(
                    Ellipse()
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                )
                .offset(y: headHeight * 0.18)

            Ellipse()
                .fill(Color.white.opacity(0.08))
                .frame(width: headWidth * 0.26, height: headHeight * 0.18)
                .offset(y: headHeight * 0.1)

            HStack(spacing: headWidth * 0.16) {
                visibleEye
                visibleEye
            }
            .offset(y: -headHeight * 0.08)

            frontalCheekAccessory
                .offset(y: headHeight * 0.18)

            PetSmile(curve: max(0.08, sceneModel.mouthCurve * 0.42))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: 16, height: 10)
                .offset(y: headHeight * 0.28)
        }
        .frame(width: headWidth * 1.18, height: headHeight * 1.26)
    }

    private var frontEar: some View {
        PetEarShape()
            .fill(palette.shell)
            .frame(width: geometry.earWidth.cg * 0.82, height: geometry.earHeight.cg * 0.88)
            .overlay(
                PetEarShape()
                    .fill(palette.belly.opacity(0.78))
                    .frame(width: geometry.earInnerWidth.cg * 0.92, height: geometry.earInnerHeight.cg * 1.04)
                    .offset(y: geometry.earHeight.cg * 0.06)
            )
            .rotationEffect(.degrees(8 + Double(sceneModel.earLift) * 0.18))
            .offset(x: 14, y: -46 - sceneModel.earLift * 0.18)
    }

    private var backEar: some View {
        PetEarShape()
            .fill(palette.shell.opacity(0.86))
            .frame(width: geometry.earWidth.cg * 0.7, height: geometry.earHeight.cg * 0.78)
            .overlay(
                PetEarShape()
                    .fill(palette.belly.opacity(0.6))
                    .frame(width: geometry.earInnerWidth.cg * 0.76, height: geometry.earInnerHeight.cg * 0.9)
                    .offset(y: geometry.earHeight.cg * 0.06)
            )
            .rotationEffect(.degrees(-8 + Double(sceneModel.earLift) * 0.14))
            .offset(x: -14, y: -44 - sceneModel.earLift * 0.14)
    }

    @ViewBuilder
    private var neckAccessory: some View {
        switch accessories.neck {
        case .scarf:
            scarfAccessory
        case .bow:
            bowAccessory
        case .collar:
            collarAccessory
        case .none:
            EmptyView()
        }
    }

    private var scarfAccessory: some View {
        ZStack {
            Capsule()
                .fill(palette.accent.opacity(0.92))
                .frame(width: geometry.scarfWidth.cg * 0.72, height: geometry.scarfHeight.cg * 0.78)

            PetScarfTailShape()
                .fill(palette.accent.opacity(0.88))
                .frame(width: geometry.scarfTailWidth.cg * 0.68, height: geometry.scarfTailHeight.cg * 0.68)
                .offset(x: -geometry.scarfWidth.cg * 0.08, y: geometry.scarfHeight.cg * 0.44)
        }
    }

    private var bowAccessory: some View {
        ZStack {
            HStack(spacing: geometry.scarfWidth.cg * 0.04) {
                Ellipse()
                    .fill(palette.accent.opacity(0.9))
                    .frame(width: geometry.scarfWidth.cg * 0.22, height: geometry.scarfHeight.cg * 0.94)
                    .rotationEffect(.degrees(-10))

                Ellipse()
                    .fill(palette.accent.opacity(0.9))
                    .frame(width: geometry.scarfWidth.cg * 0.22, height: geometry.scarfHeight.cg * 0.94)
                    .rotationEffect(.degrees(10))
            }

            RoundedRectangle(cornerRadius: geometry.scarfHeight.cg * 0.4, style: .continuous)
                .fill(palette.belly.opacity(0.96))
                .frame(width: geometry.scarfHeight.cg * 0.72, height: geometry.scarfHeight.cg * 0.84)

            HStack(spacing: geometry.scarfWidth.cg * 0.12) {
                PetScarfTailShape()
                    .fill(palette.accent.opacity(0.84))
                    .frame(width: geometry.scarfTailWidth.cg * 0.44, height: geometry.scarfTailHeight.cg * 0.44)
                    .rotationEffect(.degrees(86))

                PetScarfTailShape()
                    .fill(palette.accent.opacity(0.84))
                    .frame(width: geometry.scarfTailWidth.cg * 0.44, height: geometry.scarfTailHeight.cg * 0.44)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(-86))
            }
            .offset(y: geometry.scarfHeight.cg * 0.54)
        }
    }

    private var collarAccessory: some View {
        ZStack {
            Capsule()
                .fill(palette.accent.opacity(0.92))
                .frame(width: geometry.scarfWidth.cg * 0.72, height: geometry.scarfHeight.cg * 0.58)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )

            Circle()
                .fill(palette.glow.opacity(0.96))
                .frame(width: geometry.scarfHeight.cg * 0.82, height: geometry.scarfHeight.cg * 0.82)
                .overlay(
                    Image(systemName: character.symbols.crest)
                        .font(.system(size: geometry.scarfHeight.cg * 0.28, weight: .bold))
                        .foregroundStyle(Color.white)
                )
                .offset(x: geometry.scarfWidth.cg * 0.18, y: geometry.scarfHeight.cg * 0.44)
        }
    }

    @ViewBuilder
    private var headAccessory: some View {
        switch accessories.head {
        case .crest:
            crestAccessory
        case .flower:
            flowerAccessory
        case .crown:
            crownAccessory
        case .none:
            EmptyView()
        }
    }

    private var crestAccessory: some View {
        HStack(spacing: geometry.crestSize.cg * 0.08) {
            PetEarShape()
                .fill(palette.glow.opacity(0.9))
                .frame(width: geometry.crestSize.cg * 0.24, height: geometry.crestSize.cg * 0.34)
                .rotationEffect(.degrees(-12))

            PetEarShape()
                .fill(palette.glow.opacity(0.78))
                .frame(width: geometry.crestSize.cg * 0.2, height: geometry.crestSize.cg * 0.28)
                .rotationEffect(.degrees(18))
                .offset(y: geometry.crestSize.cg * 0.06)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private var flowerAccessory: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(palette.glow.opacity(0.58))
                    .frame(width: geometry.crestSize.cg * 0.36, height: geometry.crestSize.cg * 0.36)
                    .offset(y: -geometry.crestSize.cg * 0.26)
                    .rotationEffect(.degrees(Double(index) * 72))
            }

            Circle()
                .fill(palette.accent.opacity(0.94))
                .frame(width: geometry.crestSize.cg * 0.46, height: geometry.crestSize.cg * 0.46)
                .overlay(
                    Image(systemName: character.symbols.crest)
                        .font(.system(size: geometry.crestSize.cg * 0.18, weight: .bold))
                        .foregroundStyle(Color.white)
                )
        }
    }

    private var crownAccessory: some View {
        PetCrownShape()
            .fill(
                LinearGradient(
                    colors: [
                        palette.glow.opacity(0.95),
                        palette.accent.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: geometry.crestSize.cg * 0.94, height: geometry.crestSize.cg * 0.68)
            .overlay(
                Image(systemName: character.symbols.crest)
                    .font(.system(size: geometry.crestSize.cg * 0.18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .offset(y: geometry.crestSize.cg * 0.04)
            )
    }

    private var visibleEye: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.98))
                .frame(width: geometry.eyeWhiteWidth.cg * 0.94, height: geometry.eyeWhiteWidth.cg * 0.94)

            Circle()
                .fill(palette.accent)
                .frame(width: geometry.pupilWidth.cg * 0.88, height: geometry.pupilWidth.cg * 0.88)
                .offset(x: sceneModel.gazeOffset * 0.18, y: 0.2)

            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 2.4, height: 2.4)
                .offset(x: sceneModel.gazeOffset * 0.18 + 1.2, y: -2.6)
                .opacity(eyeOpenAmount > 0.2 ? 1 : 0)
        }
        .overlay(
            Circle()
                .stroke(palette.accent.opacity(0.18), lineWidth: 1)
        )
        .scaleEffect(y: eyeOpenAmount, anchor: .center)
    }

    @ViewBuilder
    private var frontalCheekAccessory: some View {
        switch accessories.cheeks {
        case .blush:
            HStack(spacing: geometry.blushSpacing.cg * 0.72) {
                Circle()
                    .fill(palette.blush.opacity(0.32))
                    .frame(width: geometry.blushSize.cg * 0.58, height: geometry.blushSize.cg * 0.58)
                Circle()
                    .fill(palette.blush.opacity(0.32))
                    .frame(width: geometry.blushSize.cg * 0.58, height: geometry.blushSize.cg * 0.58)
            }
        case .freckles:
            HStack(spacing: geometry.blushSpacing.cg * 0.72) {
                frecklesGroup
                frecklesGroup
            }
        case .stardust:
            HStack(spacing: geometry.blushSpacing.cg * 0.72) {
                stardustMark
                stardustMark
            }
        case .none:
            EmptyView()
        }
    }

    private var frecklesGroup: some View {
        VStack(spacing: geometry.blushSize.cg * 0.12) {
            HStack(spacing: geometry.blushSize.cg * 0.14) {
                Circle()
                    .fill(palette.blush.opacity(0.72))
                    .frame(width: geometry.blushSize.cg * 0.36, height: geometry.blushSize.cg * 0.36)
                Circle()
                    .fill(palette.blush.opacity(0.64))
                    .frame(width: geometry.blushSize.cg * 0.28, height: geometry.blushSize.cg * 0.28)
            }

            Circle()
                .fill(palette.blush.opacity(0.58))
                .frame(width: geometry.blushSize.cg * 0.32, height: geometry.blushSize.cg * 0.32)
                .offset(x: geometry.blushSize.cg * 0.12)
        }
    }

    private var stardustMark: some View {
        Image(systemName: "sparkles")
            .font(.system(size: geometry.blushSize.cg * 0.84, weight: .semibold))
            .foregroundStyle(palette.blush.opacity(0.84))
            .rotationEffect(.degrees(sceneModel.isFacingRight ? 8 : -8))
    }

    private var frontPaws: some View {
        HStack(spacing: geometry.pawSpacing.cg * 0.42) {
            paw(offset: footLiftBack * 0.24, widthScale: 0.82)
            paw(offset: footLiftFront * 0.38, widthScale: 1)
        }
        .offset(x: 12, y: 86)
    }

    private var rearPaw: some View {
        paw(offset: footLiftBack * 0.14, widthScale: 0.88)
            .offset(x: -18, y: 86)
    }

    private func paw(offset: CGFloat, widthScale: CGFloat) -> some View {
        PetPawShape()
            .fill(palette.accent)
            .frame(width: geometry.pawWidth.cg * widthScale, height: geometry.pawHeight.cg * 0.58)
            .offset(y: offset)
    }

    @ViewBuilder
    private var stateAccessory: some View {
        if sceneModel.state == .thinking {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    palette.glow.opacity(0.36 - Double(index) * 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: CGFloat(6 + index * 3), height: CGFloat(6 + index * 3))
                        .shadow(color: palette.glow.opacity(0.14 + Double(index) * 0.04), radius: 6, y: 2)
                        .offset(
                            x: CGFloat(index) * 2,
                            y: CGFloat(sin(sceneModel.haloPulse * 1.36 + Double(index) * 0.72)) * 4 - CGFloat(index * 4)
                        )
                }
            }
            .scaleEffect(1 + sceneModel.moodGlow * 0.06)
            .offset(x: 46, y: -30)
        } else if sceneModel.state == .done {
            ZStack {
                HStack(spacing: 4) {
                    Image(systemName: character.symbols.donePrimary)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.glow)

                    Image(systemName: character.symbols.doneSecondary)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white, palette.accent)
                        .offset(y: 4)
                }

                ForEach(0..<2, id: \.self) { index in
                    Image(systemName: "sparkles")
                        .font(.system(size: 9 + CGFloat(index), weight: .bold))
                        .foregroundStyle(Color.white, palette.glow)
                        .shadow(color: palette.glow.opacity(0.18), radius: 6, y: 2)
                        .offset(
                            x: CGFloat(index == 0 ? -16 : 14),
                            y: CGFloat(sin(sceneModel.haloPulse * 1.52 + Double(index) * 0.9)) * 4 - CGFloat(10 + index * 4)
                        )
                }
            }
            .shadow(color: palette.glow.opacity(0.24), radius: 6, y: 3)
            .scaleEffect(1 + sceneModel.moodGlow * 0.05)
            .offset(x: -44, y: -6)
        }
    }
}
