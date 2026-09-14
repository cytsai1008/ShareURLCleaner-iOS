import SwiftUI

struct SettingsView: View {
    @State private var model = SettingsModel()
    @State private var showAddFilter = false
    @State private var newFilterURL = ""
    @State private var showLicenses = false

    private var lastUpdatedText: String {
        guard let date = model.lastUpdated else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.ruleCount == 0 {
                    Section {
                        Label("No filter rules saved yet. Tap Update Now to download them — until then, shared URLs aren't cleaned.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Filter Lists") {
                    ForEach(model.sources) { source in
                        FilterSourceRow(source: source) { model.setEnabled(source, $0) }
                            .swipeActions {
                                if !source.isBuiltIn {
                                    Button("Remove", role: .destructive) { model.remove(source) }
                                }
                            }
                    }
                    Button("Add Filter List…") {
                        newFilterURL = ""
                        showAddFilter = true
                    }
                }

                Section {
                    Button {
                        Task { await model.updateNow() }
                    } label: {
                        HStack {
                            Text("Update Now")
                            if model.isUpdating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.isUpdating)

                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.red).font(.callout)
                    }
                }

                Section {
                    Toggle("Auto Update Daily", isOn: Binding(
                        get: { model.autoUpdate },
                        set: { model.setAutoUpdate($0) }
                    ))
                } footer: {
                    Text("Refresh the filter lists once a day in the background.")
                }

                aggressiveSection

                Section("Status") {
                    LabeledContent("Last Updated", value: lastUpdatedText)
                    LabeledContent("Rules Loaded", value: "\(model.ruleCount)")
                }

                Section {
                    Button("Third-Party Licenses") { showLicenses = true }
                }
            }
            .navigationTitle("URL Cleaner")
            .alert("Add Filter List", isPresented: $showAddFilter) {
                TextField("Filter URL", text: $newFilterURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Add") { model.add(newFilterURL) }
            }
            .alert("Third-Party Licenses", isPresented: $showLicenses) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(licensesText)
            }
        }
    }

    @ViewBuilder
    private var aggressiveSection: some View {
        Section("Aggressive Mode") {
            Picker("Follow Redirects", selection: Binding(
                get: { model.aggressiveMode },
                set: { model.setAggressiveMode($0) }
            )) {
                Text("Off").tag(RedirectResolver.Mode.off)
                Text("Selected Sites").tag(RedirectResolver.Mode.selected)
                Text("All Sites").tag(RedirectResolver.Mode.all)
            }
            .pickerStyle(.menu)

            Text(aggressiveDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if model.aggressiveMode == .selected {
                NavigationLink("Sites (\(model.aggressiveDomainCount))") {
                    AggressiveDomainsEditor(model: model)
                }
            }
        }
    }

    private var aggressiveDescription: String {
        switch model.aggressiveMode {
        case .off:
            return "Clean the shared link only. No network request, nothing leaves the device."
        case .selected:
            return "Follow shorteners and share-wrappers on the listed sites to the real link, then clean that. Those sites see one request."
        case .all:
            return "Follow every shared link to its destination before cleaning. Every site you share sees a request."
        }
    }

    private var licensesText: String {
        """
        Filter lists are fetched at runtime and carry their own licenses.

        The app icon is based on Phosphor Icons, licensed under the MIT License.
        """
    }
}

private struct FilterSourceRow: View {
    let source: FilterSource
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { source.enabled }, set: onToggle)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name.isEmpty ? source.url : source.name)
                    .font(.callout)
                if !source.name.isEmpty {
                    Text(source.url)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

private struct AggressiveDomainsEditor: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                TextEditor(text: $model.aggressiveDomains)
                    .frame(minHeight: 240)
                    .font(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("One host per line (or separated by spaces, commas or semicolons). Subdomains are matched too.")
            }
            Section {
                Button("Reset to Default") { model.resetAggressiveDomains() }
            }
        }
        .navigationTitle("Sites")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.saveAggressiveDomains() }
    }
}

#Preview {
    SettingsView()
}
