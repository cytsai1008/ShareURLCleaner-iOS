import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share-sheet entry point: pulls the shared URL/text, cleans it, and shows the result
/// with Copy / Share actions. iOS can't silently re-open the system share sheet, so we
/// surface the cleaned URL and let the user re-share or copy it.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await loadAndPresent() }
    }

    private func loadAndPresent() async {
        let input = await extractInput() ?? ""
        let rules = FilterStore.loadRules()

        // Aggressive mode makes a network call, so the UI goes up first with a "resolving…"
        // state rather than leaving the sheet blank for the length of a redirect chain.
        let resolving = ShareTextCleaner.hasUrl(input)
            && RedirectResolver.forMode(Settings.aggressiveMode,
                                        domains: Settings.parseDomains(Settings.aggressiveDomains)) != nil
        let state = ShareState(original: input, cleaned: input, noRules: rules.isEmpty,
                               resolving: resolving)
        present(state)

        let fetchFailed = FetchFlag()
        let resolve = RedirectResolver.forMode(
            Settings.aggressiveMode,
            domains: Settings.parseDomains(Settings.aggressiveDomains),
            onFailure: { fetchFailed.set() },
            clean: { UrlCleaner.clean($0, rules: rules) }
        )
        let result = await ShareTextCleaner.cleanUrls(input, rules: rules, resolve: resolve)

        state.cleaned = result.text
        state.changed = result.cleaned
        state.fetchFailed = fetchFailed.value
        state.resolving = false
    }

    private func present(_ state: ShareState) {
        let view = ShareView(
            state: state,
            onShare: { [weak self] text in self?.reshare(text) },
            onDone: { [weak self] in self?.finish() }
        )
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func reshare(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.finish() }
        present(activity, animated: true)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Returns the first URL- or text-bearing attachment as a string.
    private func extractInput() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    return url.absoluteString
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    return text
                }
            }
        }
        return nil
    }
}

/// Set from the resolver's callback, which runs off the main actor.
final class FetchFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}
