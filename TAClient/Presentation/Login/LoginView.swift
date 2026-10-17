import SwiftUI

struct LoginView: View {
    @Bindable var viewModel: LoginViewModel
    @State private var showToken = false
    @FocusState private var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable { case server, token }
    private var hasAddress: Bool { !viewModel.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                    Text(String(localized: "stream_login_headline"))
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "connection_tagline")).font(.title3).foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "connection_server_address"), systemImage: "network")
                            .font(.subheadline.weight(.semibold))
                        TextField(String(localized: "connection_address_placeholder"), text: $viewModel.serverURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                            .focused($focusedField, equals: .server)
                            .submitLabel(.go)
                            .onSubmit { beginSignIn() }
                            .accessibilityLabel(String(localized: "connection_server_address"))
                            .accessibilityIdentifier("connection.server")
                        Text(String(localized: "connection_address_help"))
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Button(action: beginSignIn) {
                        HStack(spacing: 10) {
                            if viewModel.isLoading { ProgressView().tint(.primary) }
                            Text(String(localized: "connection_sign_in"))
                                .fontWeight(.semibold)
                            Spacer(minLength: 0)
                            if !dynamicTypeSize.isAccessibilitySize { Image(systemName: "arrow.right") }
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(dynamicTypeSize.isAccessibilitySize ? .roundedRectangle(radius: 18) : .capsule)
                    .disabled(viewModel.isLoading || !hasAddress)
                    .accessibilityLabel(String(localized: "connection_sign_in"))
                    .accessibilityIdentifier("connection.sign-in")

                    Text(String(localized: "connection_gateway_help"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))

                DisclosureGroup(isExpanded: $showToken) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(String(localized: "login_token_explanation"))
                            .font(.footnote).foregroundStyle(.secondary)
                        SecureField(String(localized: "login_api_token"), text: $viewModel.apiToken)
                            .textFieldStyle(.plain)
                            .padding(14)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .token)
                            .submitLabel(.go)
                            .onSubmit { connectToken() }
                            .accessibilityLabel(String(localized: "login_api_token"))
                        Button(action: connectToken) {
                            Text(String(localized: "connection_token_button"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                        .disabled(viewModel.isLoading || !hasAddress || viewModel.apiToken.isEmpty)
                        .accessibilityLabel(String(localized: "connection_token_button"))
                    }
                    .padding(.top, 16)
                } label: {
                    Label(String(localized: "login_token_fallback"), systemImage: "key.horizontal")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 4)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showToken)

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                }

                NavigationLink(value: Route.offlineDownloads) {
                    Label(String(localized: "offline_open_saved"), systemImage: "arrow.down.circle")
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel(String(localized: "offline_open_saved"))

                Label(String(localized: showToken ? "connection_token_privacy" : "connection_privacy_help"), systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Tube Archivist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "connection_done")) { focusedField = nil }
                    .accessibilityLabel(String(localized: "connection_done"))
            }
        }
        .sheet(item: $viewModel.signInDestination) { destination in
            ServerSignInView(url: destination.url, viewModel: viewModel)
        }
    }

    private func beginSignIn() {
        guard hasAddress, !viewModel.isLoading else { return }
        focusedField = nil
        viewModel.beginServerSignIn()
    }

    private func connectToken() {
        guard hasAddress, !viewModel.apiToken.isEmpty, !viewModel.isLoading else { return }
        focusedField = nil
        Task { await viewModel.connectToken() }
    }
}
