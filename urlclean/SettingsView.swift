import SwiftUI

struct SettingsView: View {
    @State private var model = SettingsModel()

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
                Section("Filter List") {
                    TextField("Filter URL", text: $model.filterURL, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout)
                        .onSubmit { model.saveFilterURL() }
                    Button("Reset to Default") { model.resetFilterURL() }
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
                    Text("Refresh the filter list once a day in the background.")
                }

                Section("Status") {
                    LabeledContent("Last Updated", value: lastUpdatedText)
                    LabeledContent("Rules Loaded", value: "\(model.ruleCount)")
                }
            }
            .navigationTitle("URL Cleaner")
        }
    }
}

#Preview {
    SettingsView()
}
