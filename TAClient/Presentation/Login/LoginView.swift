import SwiftUI

struct LoginView: View {
    @Bindable var viewModel: LoginViewModel
    @State private var showToken = false
    @FocusState private var serverURLFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)

                Text("Tube Archivist")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(String(localized: "login_server_url"), text: $viewModel.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($serverURLFocused)
                            .onChange(of: viewModel.serverURL) {
                                let url = viewModel.serverURL
                                for scheme in ["https://", "http://"] {
                                    let doubled = scheme + scheme
                                    if url.hasPrefix(doubled) {
                                        viewModel.serverURL = String(url.dropFirst(scheme.count))
                                        return
                                    }
                                }
                            }
                        Text(String(localized: "login_server_url_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(String(localized: "login_server_explanation"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "login_server_button")) { viewModel.beginServerSignIn() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(String(localized: "login_server_button"))
                        .disabled(viewModel.isLoading)
                    DisclosureGroup(String(localized: "login_token_fallback"), isExpanded: $showToken) {
                        Text(String(localized: "login_token_explanation")).font(.caption).foregroundStyle(.secondary)
                        SecureField(String(localized: "login_api_token"), text: $viewModel.apiToken)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(String(localized: "login_api_token"))
                    }
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }

                    if showToken {
                    Button {
                        Task {
                            await viewModel.connectToken()
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(String(localized: "login_button"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || viewModel.apiToken.isEmpty)
                    .accessibilityLabel(String(localized: "login_button"))
                    }
                }
                .frame(maxWidth: 440)
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .frame(maxWidth: 520)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .geometryGroup()
        .sheet(item: $viewModel.signInDestination) { destination in
            ServerSignInView(url: destination.url, viewModel: viewModel)
        }
    }
}
