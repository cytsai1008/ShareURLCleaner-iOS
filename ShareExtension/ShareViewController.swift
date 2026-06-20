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
        let result = ShareTextCleaner.cleanFirstUrl(input, rules: rules)

        let view = ShareView(
            original: input,
            cleaned: result.text,
            changed: result.cleaned,
            noRules: rules.isEmpty,
            onShare: { [weak self] in self?.reshare(result.text) },
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
