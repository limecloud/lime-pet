import Foundation
import SwiftUI

struct PetColorToken: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double?

    func color(opacity multiplier: Double = 1) -> Color {
        Color(
            red: red,
            green: green,
            blue: blue,
            opacity: min(max((alpha ?? 1) * multiplier, 0), 1)
        )
    }
}

struct PetPaletteTokens: Codable, Hashable {
    let shell: PetColorToken
    let belly: PetColorToken
    let accent: PetColorToken
    let glow: PetColorToken
    let blush: PetColorToken
}

struct PetRenderPalette {
    let shell: Color
    let belly: Color
    let accent: Color
    let glow: Color
    let blush: Color

    static let clear = PetRenderPalette(
        shell: .clear,
        belly: .clear,
        accent: .clear,
        glow: .clear,
        blush: .clear
    )
}

private extension PetPaletteTokens {
    func resolved() -> PetRenderPalette {
        PetRenderPalette(
            shell: shell.color(),
            belly: belly.color(),
            accent: accent.color(),
            glow: glow.color(),
            blush: blush.color()
        )
    }
}

struct PetCharacterStatePalettes: Codable, Hashable {
    let idle: PetPaletteTokens
    let walking: PetPaletteTokens
    let thinking: PetPaletteTokens
    let done: PetPaletteTokens
}

struct PetCharacterMotion: Codable, Hashable {
    let walkSpeedMultiplier: Double
    let roamRadiusMultiplier: Double
    let bobAmplitudeMultiplier: Double
    let stretchMultiplier: Double
    let tailSwingMultiplier: Double
    let blinkMinFrames: Int
    let blinkMaxFrames: Int
    let ambientDelayMinSeconds: Int
    let ambientDelayMaxSeconds: Int

    func randomBlinkInterval() -> Int {
        Int.random(in: blinkMinFrames...max(blinkMinFrames, blinkMaxFrames))
    }

    func randomAmbientDelayNanoseconds() -> UInt64 {
        let seconds = UInt64(Int.random(in: ambientDelayMinSeconds...max(ambientDelayMinSeconds, ambientDelayMaxSeconds)))
        return seconds * 1_000_000_000
    }
}

struct PetCharacterDialogue: Codable, Hashable {
    let connectedIdle: [String]
    let disconnectedIdle: [String]
    let connectedWalking: [String]
    let disconnectedWalking: [String]
    let thinking: [String]
    let done: [String]

    func lines(for state: PetState, isConnected: Bool) -> [String] {
        switch state {
        case .hidden:
            return []
        case .idle:
            return isConnected ? connectedIdle : disconnectedIdle
        case .walking:
            return isConnected ? connectedWalking : disconnectedWalking
        case .thinking:
            return thinking
        case .done:
            return done
        }
    }
}

enum PetNeckAccessoryStyle: String, Codable, Hashable {
    case none
    case scarf
    case bow
    case collar
}

enum PetHeadAccessoryStyle: String, Codable, Hashable {
    case none
    case crest
    case flower
    case crown
}

enum PetTrailAccessoryStyle: String, Codable, Hashable {
    case none
    case glowDots = "glow-dots"
    case sunMotes = "sun-motes"
    case sparkles
}

enum PetCheekAccessoryStyle: String, Codable, Hashable {
    case none
    case blush
    case freckles
    case stardust
}

struct PetCharacterAccessories: Codable, Hashable {
    let neck: PetNeckAccessoryStyle
    let head: PetHeadAccessoryStyle
    let trail: PetTrailAccessoryStyle
    let cheeks: PetCheekAccessoryStyle
}

struct PetCharacterGeometry: Codable, Hashable {
    let headWidth: Double
    let headHeight: Double
    let headCornerRadius: Double
    let bellyWidth: Double
    let bellyHeight: Double
    let bellyCornerRadius: Double
    let bellyOffsetY: Double
    let highlightWidth: Double
    let highlightHeight: Double
    let highlightOffsetX: Double
    let highlightOffsetY: Double
    let earWidth: Double
    let earHeight: Double
    let earSpread: Double
    let earOffsetY: Double
    let earTilt: Double
    let earInnerWidth: Double
    let earInnerHeight: Double
    let tailWidth: Double
    let tailHeight: Double
    let tailOffsetX: Double
    let tailOffsetY: Double
    let haloSize: Double
    let shadowWidth: Double
    let shadowHeight: Double
    let pawWidth: Double
    let pawHeight: Double
    let pawSpacing: Double
    let eyeWhiteWidth: Double
    let eyeWhiteHeight: Double
    let pupilWidth: Double
    let pupilHeight: Double
    let eyeSpacing: Double
    let eyeOffsetY: Double
    let blushSize: Double
    let blushSpacing: Double
    let blushOffsetY: Double
    let mouthWidth: Double
    let mouthHeight: Double
    let mouthOffsetY: Double
    let whiskerLength: Double
    let whiskerThickness: Double
    let whiskerSideOffset: Double
    let whiskerSpacing: Double
    let whiskerRowSpacing: Double
    let whiskerOffsetY: Double
    let badgeSize: Double
    let badgeOffsetX: Double
    let badgeOffsetY: Double
    let scarfWidth: Double
    let scarfHeight: Double
    let scarfOffsetY: Double
    let scarfTailWidth: Double
    let scarfTailHeight: Double
    let scarfTailOffsetX: Double
    let scarfTailOffsetY: Double
    let crestSize: Double
    let crestOffsetY: Double
}

struct PetCharacterSymbols: Codable, Hashable {
    let menuBar: String
    let connectedStatus: String
    let disconnectedStatus: String
    let thinkingPrimary: String
    let donePrimary: String
    let doneSecondary: String
    let crest: String
}

struct PetCharacterTheme: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let switchBubble: String
    let palettes: PetCharacterStatePalettes
    let motion: PetCharacterMotion
    let dialogue: PetCharacterDialogue
    let accessories: PetCharacterAccessories
    let geometry: PetCharacterGeometry
    let symbols: PetCharacterSymbols

    func palette(for state: PetState) -> PetRenderPalette {
        switch state {
        case .hidden:
            return .clear
        case .idle:
            return palettes.idle.resolved()
        case .walking:
            return palettes.walking.resolved()
        case .thinking:
            return palettes.thinking.resolved()
        case .done:
            return palettes.done.resolved()
        }
    }
}

struct PetCharacterCatalog: Codable {
    let defaultCharacterId: String
    let characters: [PetCharacterTheme]
}

private let defaultPetCharacterBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return .main
    #endif
}()

@MainActor
final class PetCharacterLibrary {
    static let shared = PetCharacterLibrary()

    private let defaults = UserDefaults.standard
    private let selectionKey = "com.lime.pet.character.v1"
    private let catalog: PetCharacterCatalog

    init(bundle: Bundle? = nil) {
        self.catalog = Self.loadCatalog(bundle: bundle ?? defaultPetCharacterBundle)
    }

    var characters: [PetCharacterTheme] {
        catalog.characters
    }

    func selectedCharacter() -> PetCharacterTheme {
        if let selected = character(id: defaults.string(forKey: selectionKey)) {
            return selected
        }

        if let fallback = character(id: catalog.defaultCharacterId) {
            return fallback
        }

        return catalog.characters.first ?? .fallback
    }

    func character(id: String?) -> PetCharacterTheme? {
        guard let id else { return nil }
        return catalog.characters.first(where: { $0.id == id })
    }

    @discardableResult
    func selectCharacter(id: String) -> PetCharacterTheme? {
        guard let character = character(id: id) else { return nil }
        defaults.set(id, forKey: selectionKey)
        return character
    }

    private static func loadCatalog(bundle: Bundle) -> PetCharacterCatalog {
        let bundledCatalog =
            loadCatalogFile(bundle: bundle, subdirectory: nil) ??
            loadCatalogFile(bundle: bundle, subdirectory: "Resources")

        return bundledCatalog ?? PetCharacterCatalog(
            defaultCharacterId: PetCharacterTheme.fallback.id,
            characters: [PetCharacterTheme.fallback]
        )
    }

    private static func loadCatalogFile(bundle: Bundle, subdirectory: String?) -> PetCharacterCatalog? {
        guard
            let url = bundle.url(
                forResource: "character-library",
                withExtension: "json",
                subdirectory: subdirectory
            ),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(PetCharacterCatalog.self, from: data)
        else {
            return nil
        }

        return catalog
    }
}

extension PetCharacterTheme {
    static let fallback = PetCharacterTheme(
        id: "lime-scout",
        displayName: "青柠巡游",
        switchBubble: "切换到青柠巡游形态",
        palettes: PetCharacterStatePalettes(
            idle: PetPaletteTokens(
                shell: PetColorToken(red: 0.25, green: 0.63, blue: 0.89, alpha: 1),
                belly: PetColorToken(red: 0.84, green: 0.95, blue: 1.00, alpha: 1),
                accent: PetColorToken(red: 0.12, green: 0.29, blue: 0.44, alpha: 1),
                glow: PetColorToken(red: 0.53, green: 0.82, blue: 1.00, alpha: 1),
                blush: PetColorToken(red: 0.90, green: 0.67, blue: 0.78, alpha: 1)
            ),
            walking: PetPaletteTokens(
                shell: PetColorToken(red: 0.31, green: 0.72, blue: 0.55, alpha: 1),
                belly: PetColorToken(red: 0.90, green: 0.98, blue: 0.94, alpha: 1),
                accent: PetColorToken(red: 0.10, green: 0.34, blue: 0.24, alpha: 1),
                glow: PetColorToken(red: 0.57, green: 0.91, blue: 0.74, alpha: 1),
                blush: PetColorToken(red: 0.98, green: 0.72, blue: 0.74, alpha: 1)
            ),
            thinking: PetPaletteTokens(
                shell: PetColorToken(red: 0.98, green: 0.69, blue: 0.31, alpha: 1),
                belly: PetColorToken(red: 1.00, green: 0.94, blue: 0.79, alpha: 1),
                accent: PetColorToken(red: 0.54, green: 0.28, blue: 0.06, alpha: 1),
                glow: PetColorToken(red: 1.00, green: 0.82, blue: 0.54, alpha: 1),
                blush: PetColorToken(red: 0.98, green: 0.78, blue: 0.70, alpha: 1)
            ),
            done: PetPaletteTokens(
                shell: PetColorToken(red: 0.66, green: 0.48, blue: 0.91, alpha: 1),
                belly: PetColorToken(red: 0.95, green: 0.92, blue: 1.00, alpha: 1),
                accent: PetColorToken(red: 0.29, green: 0.13, blue: 0.54, alpha: 1),
                glow: PetColorToken(red: 0.83, green: 0.72, blue: 1.00, alpha: 1),
                blush: PetColorToken(red: 0.96, green: 0.75, blue: 0.82, alpha: 1)
            )
        ),
        motion: PetCharacterMotion(
            walkSpeedMultiplier: 1.0,
            roamRadiusMultiplier: 1.0,
            bobAmplitudeMultiplier: 1.0,
            stretchMultiplier: 1.0,
            tailSwingMultiplier: 1.0,
            blinkMinFrames: 90,
            blinkMaxFrames: 220,
            ambientDelayMinSeconds: 11,
            ambientDelayMaxSeconds: 19
        ),
        dialogue: PetCharacterDialogue(
            connectedIdle: [
                "我在这里帮你盯着 Lime",
                "先在旁边待命，有动静我会冒泡"
            ],
            disconnectedIdle: [
                "我还在等 Lime 连上来",
                "先陪你守着，等它上线"
            ],
            connectedWalking: [
                "我先去巡一圈桌面边缘",
                "这边我先替你看着"
            ],
            disconnectedWalking: [
                "离线时我也会继续巡航",
                "先慢慢逛着，等 Lime 回来"
            ],
            thinking: [
                "我先在旁边陪它想一会",
                "有进展我会先提醒你"
            ],
            done: [
                "刚刚那件事已经完成啦",
                "如果你愿意，我还能继续帮你叫出 Lime"
            ]
        ),
        accessories: PetCharacterAccessories(
            neck: .scarf,
            head: .crest,
            trail: .glowDots,
            cheeks: .blush
        ),
        geometry: PetCharacterGeometry(
            headWidth: 114,
            headHeight: 110,
            headCornerRadius: 34,
            bellyWidth: 58,
            bellyHeight: 62,
            bellyCornerRadius: 26,
            bellyOffsetY: 16,
            highlightWidth: 22,
            highlightHeight: 56,
            highlightOffsetX: -24,
            highlightOffsetY: -6,
            earWidth: 28,
            earHeight: 46,
            earSpread: 42,
            earOffsetY: -60,
            earTilt: 18,
            earInnerWidth: 12,
            earInnerHeight: 22,
            tailWidth: 76,
            tailHeight: 22,
            tailOffsetX: -44,
            tailOffsetY: 18,
            haloSize: 118,
            shadowWidth: 142,
            shadowHeight: 22,
            pawWidth: 18,
            pawHeight: 46,
            pawSpacing: 34,
            eyeWhiteWidth: 14,
            eyeWhiteHeight: 16,
            pupilWidth: 6.5,
            pupilHeight: 9,
            eyeSpacing: 18,
            eyeOffsetY: -14,
            blushSize: 11,
            blushSpacing: 30,
            blushOffsetY: 4,
            mouthWidth: 28,
            mouthHeight: 14,
            mouthOffsetY: 20,
            whiskerLength: 22,
            whiskerThickness: 2.4,
            whiskerSideOffset: 10,
            whiskerSpacing: 46,
            whiskerRowSpacing: 8,
            whiskerOffsetY: 10,
            badgeSize: 20,
            badgeOffsetX: 30,
            badgeOffsetY: -30,
            scarfWidth: 74,
            scarfHeight: 16,
            scarfOffsetY: 34,
            scarfTailWidth: 20,
            scarfTailHeight: 24,
            scarfTailOffsetX: 28,
            scarfTailOffsetY: 42,
            crestSize: 14,
            crestOffsetY: -36
        ),
        symbols: PetCharacterSymbols(
            menuBar: "leaf.fill",
            connectedStatus: "bolt.fill",
            disconnectedStatus: "wifi.slash",
            thinkingPrimary: "brain.head.profile",
            donePrimary: "sparkles",
            doneSecondary: "checkmark.circle.fill",
            crest: "leaf.circle.fill"
        )
    )
}
