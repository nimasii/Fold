import SwiftUI

struct LoginView: View {
    @Bindable var viewModel: LoginViewModel
    @State private var showToken = false
    @FocusState private var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable { case server, token }
    private var hasAddress: Bool { !viewModel.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasToken: Bool { !viewModel.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                introduction
                serverEntry
                signInOptions
                savedDownloads
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, StreamingStyle.gutter)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(StreamingStyle.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Fold")
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
        .onChange(of: showToken) { _, expanded in
            if !expanded && focusedField == .token { focusedField = nil }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("FoldMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                .padding(.bottom, 4)
            Text(String(localized: "stream_login_headline"))
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "connection_tagline"))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var serverEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "connection_server_address"))
                .font(.headline).accessibilityAddTraits(.isHeader)
            TextField(String(localized: "connection_address_placeholder"), text: $viewModel.serverURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(16)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: StreamingStyle.corner))
                .focused($focusedField, equals: .server)
                .submitLabel(showToken ? .next : .go)
                .onSubmit {
                    if showToken { focusedField = .token }
                    else { beginSignIn() }
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel(String(localized: "connection_server_address"))
                .accessibilityIdentifier("connection.server")
            Text(String(localized: "connection_address_help"))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signInOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: StreamingStyle.corner))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("connection.error")
            }
            Button(action: beginSignIn) {
                actionLabel("connection_sign_in", loading: viewModel.isLoading && !showToken)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(actionShape)
            .disabled(viewModel.isLoading || !hasAddress)
            .accessibilityLabel(String(localized: "connection_sign_in"))
            .accessibilityValue(viewModel.isLoading ? String(localized: "connection_connecting") : "")
            .accessibilityIdentifier("connection.sign-in")

            Text(String(localized: "connection_gateway_help"))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)
            tokenOption

            Label(String(localized: showToken ? "connection_token_privacy" : "connection_privacy_help"), systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tokenOption: some View {
        DisclosureGroup(isExpanded: $showToken) {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "login_token_explanation"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField(String(localized: "login_api_token"), text: $viewModel.apiToken)
                    .textFieldStyle(.plain)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: StreamingStyle.corner))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .token)
                    .submitLabel(.go)
                    .onSubmit { connectToken() }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel(String(localized: "login_api_token"))
                    .accessibilityIdentifier("connection.token")
                Button(action: connectToken) {
                    actionLabel("connection_token_button", loading: viewModel.isLoading)
                }
                .buttonStyle(.bordered).controlSize(.large).buttonBorderShape(actionShape)
                .disabled(viewModel.isLoading || !hasAddress || !hasToken)
                .accessibilityLabel(String(localized: "connection_token_button"))
                .accessibilityValue(viewModel.isLoading ? String(localized: "connection_connecting") : "")
                .accessibilityIdentifier("connection.token-connect")
            }
            .padding(.top, 16)
        } label: {
            Label(String(localized: "login_token_fallback"), systemImage: "key.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
        }
        .disabled(viewModel.isLoading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showToken)
    }

    private var savedDownloads: some View {
        NavigationLink(value: Route.offlineDownloads) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "offline_open_saved")).font(.headline)
                    Text(String(localized: "connection_downloads_help"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: StreamingStyle.corner))
        }
        .buttonStyle(MediaPressStyle()).foregroundStyle(.primary)
        .accessibilityLabel(String(localized: "offline_open_saved"))
        .accessibilityHint(String(localized: "connection_downloads_help"))
        .accessibilityIdentifier("connection.downloads")
    }

    private var actionShape: ButtonBorderShape {
        dynamicTypeSize.isAccessibilitySize ? .roundedRectangle(radius: StreamingStyle.corner) : .capsule
    }

    private func actionLabel(_ key: String.LocalizationValue, loading: Bool) -> some View {
        HStack(spacing: 10) {
            if loading { ProgressView().accessibilityHidden(true) }
            Text(loading ? String(localized: "connection_connecting") : String(localized: key)).fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(.vertical, 2)
    }

    private func beginSignIn() {
        guard hasAddress, !viewModel.isLoading else { return }
        focusedField = nil
        viewModel.beginServerSignIn()
    }

    private func connectToken() {
        guard hasAddress, hasToken, !viewModel.isLoading else { return }
        focusedField = nil
        Task { await viewModel.connectToken() }
    }
}
