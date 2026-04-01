import AppKit
import Foundation

enum PetPerch: String, Codable, CaseIterable {
    case left
    case center
    case right

    var roamingRadius: CGFloat {
        switch self {
        case .left, .right:
            return 84
        case .center:
            return 176
        }
    }

    var movingLabel: String {
        switch self {
        case .left:
            return "左侧巡航"
        case .center:
            return "中央巡航"
        case .right:
            return "右侧巡航"
        }
    }

    var restingLabel: String {
        switch self {
        case .left:
            return "左侧蹲守"
        case .center:
            return "中央守望"
        case .right:
            return "右侧蹲守"
        }
    }

    var thinkingLabel: String {
        switch self {
        case .left:
            return "左侧思考"
        case .center:
            return "中央思考"
        case .right:
            return "右侧思考"
        }
    }

    var doneLabel: String {
        switch self {
        case .left:
            return "左侧庆祝"
        case .center:
            return "中央庆祝"
        case .right:
            return "右侧庆祝"
        }
    }

    var placementBubble: String {
        switch self {
        case .left:
            return "左下角已就位，我会在这边陪着你"
        case .center:
            return "这里视野最好，我就在中间巡航"
        case .right:
            return "右下角已就位，我会从这边看着你"
        }
    }

    var ambientWalkingLines: [String] {
        switch self {
        case .left:
            return ["左边我先替你盯着", "我在左边巡一圈，有事就叫我"]
        case .center:
            return ["我在中间来回转转", "这里最容易第一时间提醒你"]
        case .right:
            return ["右边交给我守着", "我去右边绕一圈，消息来了就提醒你"]
        }
    }

    var ambientIdleLines: [String] {
        switch self {
        case .left:
            return ["左边先替你看着", "我在左边安静待命"]
        case .center:
            return ["我就在这里守着", "中间位置刚好，随时可以叫我"]
        case .right:
            return ["右边先替你守着", "我在右边等 Lime 的动静"]
        }
    }

    static func infer(originX: CGFloat, on screen: NSScreen, petSize: NSSize) -> PetPerch {
        let bounds = movementBounds(on: screen, petSize: petSize)
        guard bounds.upperBound > bounds.lowerBound else { return .center }

        let ratio = (originX - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        if ratio < 0.32 {
            return .left
        }
        if ratio > 0.68 {
            return .right
        }
        return .center
    }

    static func presetOriginX(on screen: NSScreen, petSize: NSSize, perch: PetPerch) -> CGFloat {
        let bounds = movementBounds(on: screen, petSize: petSize)
        switch perch {
        case .left:
            return bounds.lowerBound + 32
        case .center:
            return (bounds.lowerBound + bounds.upperBound) * 0.5
        case .right:
            return bounds.upperBound - 32
        }
    }

    private static func movementBounds(on screen: NSScreen, petSize: NSSize) -> ClosedRange<CGFloat> {
        let visible = screen.visibleFrame
        let minX = visible.minX + 4
        let maxX = visible.maxX - petSize.width - 4
        return minX...max(minX, maxX)
    }
}

private struct StoredPetPlacement: Codable {
    let perch: PetPerch
    let horizontalRatio: Double
}

@MainActor
final class PetPlacementStore {
    static let shared = PetPlacementStore()

    private let defaults = UserDefaults.standard
    private let placementKey = "com.lime.pet.placement.v1"

    func restoreOriginX(on screen: NSScreen, petSize: NSSize) -> (originX: CGFloat, perch: PetPerch)? {
        guard
            let data = defaults.data(forKey: placementKey),
            let stored = try? JSONDecoder().decode(StoredPetPlacement.self, from: data)
        else {
            return nil
        }

        let bounds = movementBounds(on: screen, petSize: petSize)
        let ratio = min(max(stored.horizontalRatio, 0), 1)
        let originX = bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) * ratio
        return (originX, stored.perch)
    }

    func save(originX: CGFloat, perch: PetPerch, on screen: NSScreen, petSize: NSSize) {
        let bounds = movementBounds(on: screen, petSize: petSize)
        let ratio: Double
        if bounds.upperBound > bounds.lowerBound {
            ratio = Double((originX - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
        } else {
            ratio = 0.5
        }

        let payload = StoredPetPlacement(
            perch: perch,
            horizontalRatio: min(max(ratio, 0), 1)
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: placementKey)
    }

    private func movementBounds(on screen: NSScreen, petSize: NSSize) -> ClosedRange<CGFloat> {
        let visible = screen.visibleFrame
        let minX = visible.minX + 4
        let maxX = visible.maxX - petSize.width - 4
        return minX...max(minX, maxX)
    }
}
