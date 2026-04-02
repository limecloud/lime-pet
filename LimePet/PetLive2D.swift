import Foundation
import AppKit
import SwiftUI
import WebKit

enum PetRendererKind: String, Codable, Hashable {
    case sprite
    case live2d
}

struct PetLive2DMotion: Codable, Hashable {
    let group: String
    let index: Int
}

struct PetLive2DStateAction: Codable, Hashable {
    let expression: String?
    let motion: PetLive2DMotion?
}

struct PetLive2DStateActions: Codable, Hashable {
    let idle: PetLive2DStateAction?
    let walking: PetLive2DStateAction?
    let thinking: PetLive2DStateAction?
    let done: PetLive2DStateAction?
}

struct PetLive2DTapActions: Codable, Hashable {
    let single: PetLive2DMotion?
    let double: PetLive2DMotion?
    let triple: PetLive2DMotion?
}

struct PetLive2DConfiguration: Codable, Hashable {
    let modelPath: String
    let scale: Double
    let offsetX: Double
    let offsetY: Double
    let emotionMap: [String: Int]
    let stateActions: PetLive2DStateActions
    let tapActions: PetLive2DTapActions

    func resolvedExpressions(from rawValues: [CompanionLive2DExpressionValue]) -> [Int] {
        rawValues.compactMap { value in
            switch value {
            case .index(let index):
                return index
            case .tag(let tag):
                return emotionMap[tag.lowercased()]
            }
        }
    }

    func resolvedExpressions(from tags: [String]) -> [Int] {
        tags.compactMap { emotionMap[$0.lowercased()] }
    }

    func resolvedStateAction(for state: PetState) -> PetLive2DResolvedActionContent? {
        let sourceAction: PetLive2DStateAction?
        switch state {
        case .hidden:
            return nil
        case .idle:
            sourceAction = stateActions.idle
        case .walking:
            sourceAction = stateActions.walking
        case .thinking:
            sourceAction = stateActions.thinking
        case .done:
            sourceAction = stateActions.done
        }

        guard let sourceAction else { return nil }
        let expressions = resolvedExpressions(from: sourceAction.expression.map { [$0] } ?? [])
        return PetLive2DResolvedActionContent(
            expressionIndices: expressions,
            motion: sourceAction.motion
        )
    }
}

struct PetLive2DResolvedActionContent: Hashable {
    let expressionIndices: [Int]
    let motion: PetLive2DMotion?

    var hasEffect: Bool {
        !expressionIndices.isEmpty || motion != nil
    }
}

struct PetLive2DQueuedAction: Hashable {
    let id: Int
    let expressionIndices: [Int]
    let motion: PetLive2DMotion?

    init(id: Int, content: PetLive2DResolvedActionContent) {
        self.id = id
        self.expressionIndices = content.expressionIndices
        self.motion = content.motion
    }
}

enum PetLive2DTapKind {
    case single
    case double
    case triple
}

private enum PetLive2DHostMessageType: String {
    case loadModel = "load-model"
    case unloadModel = "unload-model"
    case setFacing = "set-facing"
    case setHidden = "set-hidden"
    case playAction = "play-action"
}

private let petLive2DBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return .main
    #endif
}()

struct PetLive2DHostView: NSViewRepresentable {
    @ObservedObject var sceneModel: PetSceneModel
    let configuration: PetLive2DConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(bundle: petLive2DBundle)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let hidden = sceneModel.state == .hidden
        context.coordinator.update(
            webView: webView,
            configuration: configuration,
            facingRight: sceneModel.isFacingRight,
            hidden: hidden,
            queuedAction: sceneModel.live2dQueuedAction
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let bundle: Bundle
        private var isReady = false
        private var pendingScripts: [String] = []
        private var lastModelSignature: String?
        private var lastFacingRight: Bool?
        private var lastHidden: Bool?
        private var lastActionID: Int?

        init(bundle: Bundle) {
            self.bundle = bundle
            super.init()
        }

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.setValue(false, forKey: "drawsBackground")
            webView.setValue(NSColor.clear, forKey: "underPageBackgroundColor")

            if let indexURL = bundle.url(forResource: "index", withExtension: "html", subdirectory: "live2d-runtime") {
                let resourceRoot = indexURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                webView.loadFileURL(indexURL, allowingReadAccessTo: resourceRoot)
            }

            return webView
        }

        func update(
            webView: WKWebView,
            configuration: PetLive2DConfiguration,
            facingRight: Bool,
            hidden: Bool,
            queuedAction: PetLive2DQueuedAction?
        ) {
            let modelSignature = "\(configuration.modelPath)|\(configuration.scale)|\(configuration.offsetX)|\(configuration.offsetY)"
            if modelSignature != lastModelSignature {
                lastModelSignature = modelSignature
                send(
                    type: .loadModel,
                    payload: [
                        "modelPath": configuration.modelPath,
                        "scale": configuration.scale,
                        "offsetX": configuration.offsetX,
                        "offsetY": configuration.offsetY
                    ],
                    to: webView
                )
            }

            if facingRight != lastFacingRight {
                lastFacingRight = facingRight
                send(
                    type: .setFacing,
                    payload: ["facingRight": facingRight],
                    to: webView
                )
            }

            if hidden != lastHidden {
                lastHidden = hidden
                send(
                    type: .setHidden,
                    payload: ["hidden": hidden],
                    to: webView
                )
            }

            if let queuedAction, queuedAction.id != lastActionID {
                lastActionID = queuedAction.id
                var payload: [String: Any] = [
                    "expressionIndices": queuedAction.expressionIndices
                ]
                if let motion = queuedAction.motion {
                    payload["motion"] = [
                        "group": motion.group,
                        "index": motion.index
                    ]
                }
                send(type: .playAction, payload: payload, to: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            for script in pendingScripts {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
            pendingScripts.removeAll()
        }

        private func send(type: PetLive2DHostMessageType, payload: [String: Any], to webView: WKWebView) {
            guard
                JSONSerialization.isValidJSONObject(payload),
                let data = try? JSONSerialization.data(withJSONObject: [
                    "type": type.rawValue,
                    "payload": payload
                ], options: []),
                let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            let script = "window.LimePetLive2D && window.LimePetLive2D.receive(\(json));"
            if isReady {
                webView.evaluateJavaScript(script, completionHandler: nil)
            } else {
                pendingScripts.append(script)
            }
        }
    }
}
