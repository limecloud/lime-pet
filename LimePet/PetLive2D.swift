import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
    let emotionActions: [String: PetLive2DStateAction]?
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

    func resolvedIncomingAction(
        rawExpressions: [CompanionLive2DExpressionValue],
        emotionTags: [String],
        preferredMotion: PetLive2DMotion?
    ) -> PetLive2DResolvedActionContent? {
        let lowercasedTags = emotionTags.map { $0.lowercased() }
        let resolved = resolvedExpressions(from: rawExpressions) + resolvedExpressions(from: lowercasedTags)
        var expressionIndices: [Int] = []
        var seenIndices = Set<Int>()
        for index in resolved where seenIndices.insert(index).inserted {
            expressionIndices.append(index)
        }

        var motion = preferredMotion
        for tag in lowercasedTags {
            guard let action = emotionActions?[tag] else { continue }

            for index in resolvedExpressions(from: action.expression.map { [$0] } ?? [])
            where seenIndices.insert(index).inserted {
                expressionIndices.append(index)
            }

            if motion == nil {
                motion = action.motion
            }
        }

        let content = PetLive2DResolvedActionContent(
            expressionIndices: expressionIndices,
            motion: motion
        )
        return content.hasEffect ? content : nil
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
        let content = PetLive2DResolvedActionContent(
            expressionIndices: resolvedExpressions(from: sourceAction.expression.map { [$0] } ?? []),
            motion: sourceAction.motion
        )
        return content.hasEffect ? content : nil
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
        private lazy var schemeHandler = ResourceSchemeHandler(bundle: bundle)
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
            configuration.userContentController = makeUserContentController()
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: Self.resourceScheme)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.setValue(false, forKey: "drawsBackground")
            webView.setValue(NSColor.clear, forKey: "underPageBackgroundColor")

            if let indexURL = runtimeIndexURL() {
                NSLog("[PetLive2DHost] load index \(indexURL.absoluteString)")
                webView.load(URLRequest(url: indexURL))
            } else {
                NSLog("[PetLive2DHost] missing runtime index")
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
            let resolvedModelPath = resolvedModelPath(for: configuration.modelPath)
            let modelSignature = "\(resolvedModelPath)|\(configuration.scale)|\(configuration.offsetX)|\(configuration.offsetY)"
            if modelSignature != lastModelSignature {
                lastModelSignature = modelSignature
                send(
                    type: .loadModel,
                    payload: [
                        "modelPath": resolvedModelPath,
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
            NSLog("[PetLive2DHost] didFinish navigation")
            isReady = true
            for script in pendingScripts {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
            pendingScripts.removeAll()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[PetLive2DWeb][navigation] \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[PetLive2DWeb][provisional] \(error.localizedDescription)")
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
            NSLog("[PetLive2DHost] send \(type.rawValue) ready=\(isReady)")
            if isReady {
                webView.evaluateJavaScript(script, completionHandler: nil)
            } else {
                pendingScripts.append(script)
            }
        }

        private func runtimeIndexURL() -> URL? {
            guard let resourcePath = runtimeIndexResourcePath() else {
                return nil
            }

            return URL(string: "\(Self.resourceScheme)://\(Self.resourceHost)/\(resourcePath)")
        }

        private func runtimeIndexResourcePath() -> String? {
            if bundle.url(forResource: "index", withExtension: "html", subdirectory: "live2d-runtime") != nil {
                return "live2d-runtime/index.html"
            }

            if bundle.url(forResource: "index", withExtension: "html") != nil {
                return "index.html"
            }

            return nil
        }

        private func makeUserContentController() -> WKUserContentController {
            let controller = WKUserContentController()
            controller.add(self, name: "live2dLog")
            controller.addUserScript(
                WKUserScript(
                    source: Self.consoleBridgeScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
            return controller
        }

        private func resolvedModelPath(for logicalPath: String) -> String {
            if let directURL = URL(string: logicalPath), directURL.scheme != nil {
                return logicalPath
            }

            let nsLogicalPath = logicalPath as NSString
            let fileName = nsLogicalPath.lastPathComponent as NSString
            let resourceName = fileName.deletingPathExtension
            let resourceExtension = fileName.pathExtension.isEmpty ? nil : fileName.pathExtension
            let subdirectory = nsLogicalPath.deletingLastPathComponent

            if !subdirectory.isEmpty,
               bundle.url(
                    forResource: resourceName,
                    withExtension: resourceExtension,
                    subdirectory: subdirectory
               ) != nil {
                return logicalPath
            }

            if bundle.url(forResource: resourceName, withExtension: resourceExtension) != nil {
                return "./\(fileName)"
            }

            return logicalPath
        }

        private static let consoleBridgeScript = """
        (() => {
          const post = (level, values) => {
            try {
              window.webkit.messageHandlers.live2dLog.postMessage({
                level,
                values: values.map((value) => {
                  if (typeof value === "string") {
                    return value;
                  }
                  try {
                    return JSON.stringify(value);
                  } catch (error) {
                    return String(value);
                  }
                })
              });
            } catch (error) {
            }
          };

          for (const level of ["log", "warn", "error"]) {
            const original = console[level];
            console[level] = (...args) => {
              post(level, args);
              original.apply(console, args);
            };
          }

          window.addEventListener("error", (event) => {
            post("error", [event.message || "window error"]);
          });

          window.addEventListener("unhandledrejection", (event) => {
            post("error", ["unhandledrejection", event.reason]);
          });
        })();
        """

        private static let resourceScheme = "limepet"
        private static let resourceHost = "bundle"

        final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
            private let rootURL: URL

            init(bundle: Bundle) {
                self.rootURL = bundle.bundleURL.standardizedFileURL
                super.init()
            }

            func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
                guard
                    let requestURL = urlSchemeTask.request.url,
                    requestURL.scheme == Coordinator.resourceScheme,
                    requestURL.host == Coordinator.resourceHost
                else {
                    fail(urlSchemeTask, code: NSURLErrorBadURL, description: "Invalid Live2D resource URL")
                    return
                }

                let relativePath = requestURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let targetURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
                guard targetURL.path.hasPrefix(rootURL.path) else {
                    fail(urlSchemeTask, code: NSURLErrorNoPermissionsToReadFile, description: "Live2D resource outside bundle")
                    return
                }

                guard let data = try? Data(contentsOf: targetURL) else {
                    fail(urlSchemeTask, code: NSURLErrorFileDoesNotExist, description: "Missing Live2D resource: \(relativePath)")
                    return
                }

                let response = URLResponse(
                    url: requestURL,
                    mimeType: Self.mimeType(for: targetURL),
                    expectedContentLength: data.count,
                    textEncodingName: Self.textEncodingName(for: targetURL)
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }

            func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            }

            private func fail(_ task: any WKURLSchemeTask, code: Int, description: String) {
                task.didFailWithError(
                    NSError(
                        domain: NSURLErrorDomain,
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: description]
                    )
                )
            }

            private static func mimeType(for url: URL) -> String {
                if let type = UTType(filenameExtension: url.pathExtension),
                   let mimeType = type.preferredMIMEType {
                    return mimeType
                }

                switch url.pathExtension.lowercased() {
                case "moc3":
                    return "application/octet-stream"
                default:
                    return "application/octet-stream"
                }
            }

            private static func textEncodingName(for url: URL) -> String? {
                switch url.pathExtension.lowercased() {
                case "html", "js", "json", "css", "txt":
                    return "utf-8"
                default:
                    return nil
                }
            }
        }
    }
}

extension PetLive2DHostView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == "live2dLog",
            let body = message.body as? [String: Any],
            let level = body["level"] as? String
        else {
            return
        }

        let values = (body["values"] as? [String]) ?? []
        NSLog("[PetLive2DWeb][\(level)] \(values.joined(separator: " | "))")
    }
}
