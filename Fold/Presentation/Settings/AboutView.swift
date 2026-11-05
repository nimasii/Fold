import SwiftUI

struct AboutView: View {
    private var vlcName: String {
        #if targetEnvironment(macCatalyst)
        "libVLC"
        #else
        "MobileVLCKit"
        #endif
    }
    private var vlcLicense: String {
        #if targetEnvironment(macCatalyst)
        let source = "libVLC is developed by VideoLAN and is statically linked through SwiftVLC. Complete Fold source and the exact library sources/rebuild instructions are available at:\nhttps://github.com/nimasii/Fold/blob/main/Mac/RELINKING.md\n\n"
        guard let url = Bundle.main.url(forResource: "libVLC-LGPL-2.1", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return source + "LGPL-2.1-or-later — VideoLAN" }
        return source + text
        #else
        return String(localized: "about_license_lgpl_body")
        #endif
    }

    private var swiftVLCLicense: String {
        guard let url = Bundle.main.url(forResource: "SwiftVLC-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "MIT — Omar Albeik" }
        return text
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    FoldWordmark()
                    Text(String(localized: "cinema_tagline")).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            }.listRowBackground(Color.clear)
            Section {
                HStack {
                    Text(String(localized: "about_version"))
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text(String(localized: "about_description"))
                    .font(.subheadline)
            } header: {
                Text(String(localized: "about_header"))
            }

            Section {
                Text(String(localized: "about_disclaimer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "about_disclaimer_header"))
            }

            Section {
                #if targetEnvironment(macCatalyst)
                NavigationLink {
                    LicenseDetailView(title: "SwiftVLC", license: swiftVLCLicense)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SwiftVLC")
                        Text("MIT — Omar Albeik").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("SwiftVLC")
                #endif
                NavigationLink {
                    LicenseDetailView(
                        title: vlcName,
                        license: vlcLicense
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vlcName)
                        Text("LGPL-2.1 — VideoLAN")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(String(localized: "about_license_vlc"))

                NavigationLink {
                    LicenseDetailView(
                        title: "Fold",
                        license: String(localized: "about_license_apache_body")
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fold")
                        Text("Apache-2.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(String(localized: "about_license_app"))
            } header: {
                Text(String(localized: "about_licenses"))
            }

            Section {
                Link(destination: URL(string: "https://github.com/nimasii/Fold")!) {
                    Label(String(localized: "about_link_source"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityLabel(String(localized: "about_link_source"))

                Link(destination: URL(string: "https://github.com/nimasii/Fold/issues")!) {
                    Label(String(localized: "about_link_support"), systemImage: "questionmark.circle")
                }
                .accessibilityLabel(String(localized: "about_link_support"))

                Link(destination: URL(string: "https://github.com/tubearchivist/tubearchivist")!) {
                    Label("Tube Archivist", systemImage: "server.rack")
                }
                .accessibilityLabel("Tube Archivist")
            } header: {
                Text(String(localized: "about_links"))
            }
        }
        .foldReadingSurface()
        .navigationTitle(String(localized: "about_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseDetailView: View {
    let title: String
    let license: String

    var body: some View {
        ScrollView {
            Text(license)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: 720, alignment: .leading)
                .padding(StreamingStyle.gutter)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .foldReadingSurface()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
