import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(AppRouter.self) private var router
    @Environment(AuthState.self) private var authState
    @State private var showLogoutConfirmation = false

    var body: some View {
        Form {
            Section {
                if let address = authState.serverURL, let host = URL(string: address)?.host {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "server.rack").accessibilityHidden(true)
                        Text(host).fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(String(localized: "stream_connection"))
                            .accessibilityValue(host)
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                }
            } header: { Text(String(localized: "stream_connection")) }

            Section {
                Toggle(
                    String(localized: "settings_double_tap_seek"),
                    isOn: viewModel.doubleTapToSeekBinding
                )
                .accessibilityLabel(String(localized: "settings_double_tap_seek"))

                if viewModel.isDoubleTapToSeekEnabled {
                    Picker(
                        String(localized: "settings_seek_interval"),
                        selection: viewModel.seekIntervalBinding
                    ) {
                        ForEach(SponsorBlockSettings.seekIntervalOptions, id: \.self) { interval in
                            Text(String(localized: "settings_seek_seconds \(interval)")).tag(interval)
                        }
                    }
                    .accessibilityLabel(String(localized: "settings_seek_interval"))
                }
            } header: {
                Text(String(localized: "settings_player"))
            }


            Section {
                Toggle(
                    String(localized: "settings_sponsorblock_enabled"),
                    isOn: viewModel.sponsorBlockEnabledBinding
                )
                .accessibilityLabel(String(localized: "settings_sponsorblock_enabled"))
            } header: {
                Text(String(localized: "settings_sponsorblock"))
            } footer: {
                Text(String(localized: "settings_sponsorblock_description"))
            }

            if viewModel.isSponsorBlockEnabled {
                Section {
                    ForEach(SponsorCategory.allCases) { category in
                        Toggle(
                            category.label,
                            isOn: viewModel.binding(for: category)
                        )
                        .accessibilityLabel(category.label)
                    }
                } header: {
                    Text(String(localized: "settings_sponsorblock_categories"))
                }
            }
            if authState.isAuthenticated {
                Section {
                    Button(String(localized: "video_list_logout"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        showLogoutConfirmation = true
                    }
                    .accessibilityLabel(String(localized: "video_list_logout"))
                    .accessibilityIdentifier("settings.logout")
                }
            }
            Section {
                Button {
                    router.navigate(to: .about)
                } label: {
                    HStack {
                        Text(String(localized: "settings_about"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(String(localized: "settings_about"))
            }
        }
        .confirmationDialog(String(localized: "video_list_logout"), isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
            Button(String(localized: "video_list_logout"), role: .destructive) { router.handleUnauthorized() }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: { Text(String(localized: "cinema_logout_help")) }
        .formStyle(.grouped)
        .foldReadingSurface()
        .navigationTitle(String(localized: "settings_title"))
        .navigationBarTitleDisplayMode(.large)
    }
}
