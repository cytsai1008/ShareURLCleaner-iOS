import SwiftUI
import UIKit

struct ShareView: View {
    let original: String
    let cleaned: String
    let changed: Bool
    let noRules: Bool
    let onShare: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if noRules {
                    Section {
                        Label("No filter rules saved yet. Open URL Cleaner and tap Update Now to download them.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Cleaned URL") {
                    Text(cleaned).font(.callout).textSelection(.enabled)
                }
                if changed {
                    Section("Original") {
                        Text(original).font(.callout).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = cleaned
                        onDone()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        onShare()
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle(changed ? "URL Cleaned" : "Nothing to Clean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
