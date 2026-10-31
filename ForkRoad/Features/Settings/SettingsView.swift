import SwiftUI
import SwiftData
import UserNotifications
import PickerCore

/// Your name, search defaults, appearance, notifications, data, and credits.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("appearance") private var appearance: AppearanceChoice = .system
    @AppStorage("didOnboard") private var didOnboard = true
    @State private var name = Identity.displayName ?? ""
    @State private var visitReminders = VisitFollowUp.remindersOn
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmClear = false
    @State private var clearedHistory = false
    @State private var replayWelcome = false
    @State private var shareStats = UsageStats.isOn

    private let radiusOptions: [Double] = [0.5, 1, 2, 3, 5, 10]

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section {
                    TextField("Your first name", text: $name)
                        .textContentType(.givenName)
                        .onSubmit(saveName)
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Shown to friends when you vote on group picks.")
                }

                Section("Searching") {
                    Picker("Search radius", selection: $model.radiusMiles) {
                        ForEach(radiusOptions, id: \.self) { miles in
                            Text(miles < 1 ? "½ mi" : "\(Int(miles)) mi").tag(miles)
                        }
                        if !radiusOptions.contains(model.radiusMiles) {
                            Text(model.radiusLabel).tag(model.radiusMiles)
                        }
                    }
                    Toggle("No fast food", isOn: $model.excludeFastFood)
                    Picker("Diet", selection: $model.diet) {
                        ForEach(DietFilter.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Ask “How was it?”", isOn: $visitReminders)
                        .onChange(of: visitReminders) { VisitFollowUp.remindersOn = visitReminders }
                    HStack {
                        Text("Group pick alerts")
                        Spacer()
                        Text(notificationLabel).foregroundStyle(Theme.muted)
                    }
                    if notificationStatus == .notDetermined && FirebaseSetup.isConfigured {
                        Button("Turn on group alerts") {
                            Task {
                                await PushTokens.requestGroupAlerts()
                                await refreshNotificationStatus()
                            }
                        }
                    } else if notificationStatus == .denied {
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("After you get directions somewhere, ForkRoad asks how it went and files your answer: Loved it adds it to Favorites, Never again blacklists it.")
                }

                Section {
                    Toggle("Share anonymous usage counts", isOn: $shareStats)
                        .tint(Theme.saffron)
                        .onChange(of: shareStats) { UsageStats.isOn = shareStats }
                } footer: {
                    Text("Daily totals only, like how many spins happened today. Nothing about you, your places, or your location is included.")
                }

                Section("Your data") {
                    Button(clearedHistory ? "Spin history cleared" : "Clear spin history", role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(clearedHistory)
                    Button("Show the welcome screens again") {
                        // Shown once this sheet has fully closed, so the two don't collide.
                        replayWelcome = true
                        dismiss()
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Restaurant data", value: "Apple Maps")
                    NavigationLink("Credits") { AcknowledgementsView() }
                } header: {
                    Text("About")
                } footer: {
                    Text("Created by Chip Mullins\nMade with ♥ in Lexington, KY.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveName(); dismiss() }.bold()
                }
            }
            .confirmationDialog("Clear spin history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive, action: clearHistory)
            } message: {
                Text("Spins will be able to repeat places you picked this week.")
            }
            .task { await refreshNotificationStatus() }
        }
        .onDisappear { if replayWelcome { didOnboard = false } }
        .presentationBackground(Theme.night)
    }

    private var notificationLabel: String {
        guard FirebaseSetup.isConfigured else { return "Needs Firebase setup" }
        switch notificationStatus {
        case .authorized, .ephemeral: return "On"
        case .provisional: return "Quiet"
        case .denied: return "Off"
        default: return "Not set up"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { Identity.displayName = trimmed }
    }

    private func clearHistory() {
        // One by one (not a batch delete) so iCloud sync and open lists see it.
        let records = (try? context.fetch(FetchDescriptor<SpinRecord>())) ?? []
        records.forEach(context.delete)
        try? context.save()
        clearedHistory = true
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
