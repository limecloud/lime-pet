import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct LimePetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: PetCoordinator?
    private var pendingIncomingURL: URL?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleIncomingURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let configuration = LaunchConfiguration.current()
        let coordinator = PetCoordinator(configuration: configuration)
        coordinator.start()
        self.coordinator = coordinator
        if let pendingIncomingURL {
            coordinator.handleIncomingURL(pendingIncomingURL)
            self.pendingIncomingURL = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    @objc private func handleIncomingURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else {
            return
        }

        if let coordinator {
            Task { @MainActor in
                coordinator.handleIncomingURL(url)
            }
        } else {
            pendingIncomingURL = url
        }
    }
}
