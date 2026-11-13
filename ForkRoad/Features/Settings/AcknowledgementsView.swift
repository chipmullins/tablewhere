import SwiftUI

/// Credits: who made ForkRoad, the services it uses, and open-source
/// licenses with each one's full text (required by the
/// SIL Open Font License and the Apache License for software we ship).
/// License files live in Licenses/ and are bundled as resources.
struct AcknowledgementsView: View {
    struct Credit: Identifiable {
        let name: String
        let detail: String
        let license: String
        /// File in Licenses/, without the .txt extension.
        let file: String
        var id: String { name }
    }

    static let credits: [Credit] = [
        Credit(name: "Outfit", detail: "Copyright 2021 The Outfit Project Authors",
               license: "SIL Open Font License 1.1", file: "Outfit-OFL"),
        Credit(name: "DM Sans", detail: "Copyright 2014 The DM Sans Project Authors",
               license: "SIL Open Font License 1.1", file: "DMSans-OFL"),
        Credit(name: "Firebase iOS SDK", detail: "Copyright Google LLC",
               license: "Apache License 2.0", file: "Apache-2.0"),
        Credit(name: "GoogleUtilities, GoogleDataTransport, Promises, GTMSessionFetcher",
               detail: "Copyright Google LLC (components of the Firebase SDK)",
               license: "Apache License 2.0", file: "Apache-2.0"),
        Credit(name: "gRPC and Abseil", detail: "Copyright the gRPC Authors and the Abseil Authors",
               license: "Apache License 2.0", file: "Apache-2.0"),
        Credit(name: "LevelDB", detail: "Copyright 2011 The LevelDB Authors",
               license: "BSD 3-Clause License", file: "LevelDB-BSD"),
        Credit(name: "nanopb", detail: "Copyright 2011 Petteri Aimonen",
               license: "zlib License", file: "nanopb-zlib"),
        Credit(name: "BoringSSL", detail: "Copyright the OpenSSL Project, Eric Young, and Google",
               license: "OpenSSL, SSLeay, and ISC Licenses", file: "BoringSSL"),
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tablewhere")
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.text)
                    Text("Created by Chip Mullins")
                        .font(Theme.body(15, .semibold))
                        .foregroundStyle(Theme.accentText)
                    Text("Made in Lexington, Kentucky.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Theme.surface)

            Section("Data and services") {
                creditRow("Maps and restaurant data",
                          "Apple Maps. Map data © Apple and its data providers; see Legal on any map.")
                creditRow("Group voting",
                          "Firebase, by Google (sign-in, real-time data, and the web vote page).")
                creditRow("Icons", "SF Symbols, by Apple.")
                creditRow("Sync", "Your lists sync through your own iCloud account.")
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(Self.credits) { credit in
                    NavigationLink {
                        LicenseTextView(credit: credit)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credit.name).foregroundStyle(Theme.text)
                            Text(credit.license)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Open-source fonts and software")
            } footer: {
                Text("Tablewhere is built with these open-source fonts and libraries. Tap one for its full license. Thank you to their authors.")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.night)
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(Theme.text)
            Text(detail).font(Theme.body(12)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct LicenseTextView: View {
    let credit: AcknowledgementsView.Credit

    private var text: String {
        // Licenses/ is bundled as a folder; fall back to the bundle root just in case.
        let url = Bundle.main.url(forResource: credit.file, withExtension: "txt", subdirectory: "Licenses")
            ?? Bundle.main.url(forResource: credit.file, withExtension: "txt")
        guard let url,
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "\(credit.license)\n\nThe full license text is in the Tablewhere source code (Licenses/\(credit.file).txt)."
        }
        return contents
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(credit.detail)
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.text)
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.night)
        .navigationTitle(credit.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
