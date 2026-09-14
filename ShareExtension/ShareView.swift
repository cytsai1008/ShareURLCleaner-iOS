import SwiftUI
import UIKit
import Observation

/// What the share sheet shows. Filled in twice: once immediately with the raw input, then
/// again when cleaning (and any redirect following) finishes.
@MainActor
@Observable
final class ShareState {
    let original: String
    var cleaned: String
    var changed = false
    var noRules: Bool
    var resolving: Bool
    var fetchFailed = false

    init(original: String, cleaned: String, noRules: Bool, resolving: Bool) {
        self.original = original
        self.cleaned = cleaned
        self.noRules = noRules
        self.resolving = resolving
    }
}

struct ShareView: View {
    @Bindable var state: ShareState
    let onShare: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if state.noRules {
                    notice("No filter rules saved yet. Open URL Cleaner and tap Update Now to download them.")
                } else if state.fetchFailed {
                    notice("Couldn't follow the redirect — sharing the link as-is.")
                }

                Section("Cleaned URL") {
                    if state.resolving {
                        HStack {
                            ProgressView()
                            Text("Following redirect…").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    Text(state.cleaned).font(.callout).textSelection(.enabled)
                }
                if state.changed {
                    Section("Original") {
                        Text(state.original).font(.callout).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = state.cleaned
                        onDone()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        onShare(state.cleaned)
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(state.resolving)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private var title: String {
        if state.resolving { return "Cleaning…" }
        return state.changed ? "URL Cleaned" : "Nothing to Clean"
    }

    private func notice(_ text: String) -> some View {
        Section {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
