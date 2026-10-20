import SwiftUI

struct DownloadQueueView: View {
    @State var viewModel: DownloadQueueViewModel
    @State private var pendingDeletion: DownloadItem?
    @FocusState private var isAddingFocused: Bool
    @Environment(AuthState.self) private var authState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let nearEnd = Set(viewModel.items.suffix(5).map(\.id))
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.items.isEmpty {
                LoadingView()
            } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.refresh() }
                }
            } else if viewModel.items.isEmpty && !viewModel.isLoading && viewModel.downloadProgress.isEmpty {
                ContentUnavailableView(
                    String(localized: "download_queue_empty"),
                    systemImage: "arrow.down.circle"
                )
            } else {
                List {
                    ForEach(viewModel.items, id: \.id) { item in
                        DownloadItemRow(item: item)
                            .onAppear {
                                if nearEnd.contains(item.id) {
                                    Task { await viewModel.loadMoreIfNeeded() }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    pendingDeletion = item
                                } label: {
                                    Label(String(localized: "download_action_delete"), systemImage: "trash")
                                }.tint(.red)

                                if viewModel.filter == "pending" {
                                    Button {
                                        Task { await viewModel.updateStatus(videoId: item.youtubeId, status: "ignore") }
                                    } label: {
                                        Label(String(localized: "download_action_ignore"), systemImage: "eye.slash")
                                    }
                                    .tint(.orange)
                                } else {
                                    Button {
                                        Task { await viewModel.updateStatus(videoId: item.youtubeId, status: "pending") }
                                    } label: {
                                        Label(String(localized: "download_action_pending"), systemImage: "arrow.down.circle")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Task { await viewModel.downloadItem(videoId: item.youtubeId) }
                                } label: {
                                    Label(String(localized: "download_action_download"), systemImage: "arrow.down.circle.fill")
                                }
                                .tint(.green)
                            }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .listStyle(.plain)
                .animation(reduceMotion ? nil : .default, value: viewModel.items)
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        // Progress banner + inline error are rendered as a TOP SAFE-AREA INSET, not as
        // siblings above the List. A safeAreaInset adjusts the scroll view's content inset,
        // which preserves `contentOffset` — so the banner appearing/resizing/disappearing
        // (every batch start/finish, and each poll tick during active downloads) no longer
        // reflows the List and throws the scroll to the top. Previously these lived inside a
        // `.geometryGroup()`'d VStack directly above the List; inserting/animating them
        // re-laid the whole subtree and reset the List's scroll during active downloads.
        // The filter remains stable while progress and error content change below it.
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                queueControls.padding(.horizontal, StreamingStyle.gutter).padding(.vertical, 8)
                if !viewModel.downloadProgress.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(viewModel.downloadProgress, id: \.id) { info in
                            TaskNotificationBanner(info: info)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if let error = viewModel.errorMessage, !viewModel.items.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            viewModel.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(String(localized: "dismiss"))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.fill.tertiary)
                }
            }
            // Opaque chrome background so scrolled List content doesn't show through the
            // inset region; the filter keeps its own stable height.
            .background(StreamingStyle.background, ignoresSafeAreaEdges: [])
        }
        // Animate the banner/error inset appearing/disappearing on batch start/finish.
        .animation(reduceMotion ? nil : .default, value: viewModel.downloadProgress.isEmpty)
        .safeAreaInset(edge: .top) {
            if authState.isPrivileged {
                HStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField(String(localized: "download_add_placeholder"), text: Bindable(viewModel).addInput)
                            .textFieldStyle(.plain)
                            .focused($isAddingFocused)
                            .accessibilityLabel(String(localized: "download_add_placeholder"))
                            .accessibilityIdentifier("queue.add-input")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                isAddingFocused = false
                                Task { await viewModel.addToQueue() }
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))

                    Button {
                        isAddingFocused = false
                        Task { await viewModel.addToQueue() }
                    } label: {
                        if viewModel.isAdding {
                            ProgressView()
                        } else {
                            Text(String(localized: "download_add_button"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel(String(localized: "download_add_button"))
                    .accessibilityIdentifier("queue.add")
                    .disabled(viewModel.addInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAdding)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(StreamingStyle.background, ignoresSafeAreaEdges: [])
            }
        }
        .confirmationDialog(String(localized: "download_action_delete"), isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            Button(String(localized: "download_action_delete"), role: .destructive) {
                if let item = pendingDeletion { Task { await viewModel.deleteItem(videoId: item.youtubeId) } }
                pendingDeletion = nil
            }
            Button(String(localized: "cancel"), role: .cancel) { pendingDeletion = nil }
        } message: { if let item = pendingDeletion { Text(item.title) } }
        .background(StreamingStyle.background)
        .navigationTitle(String(localized: "nav_queue"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SectionMenu {
                    ForEach(["pending", "ignore"], id: \.self) { filter in
                        Button { viewModel.filter = filter } label: {
                            let label = String(localized: filter == "pending" ? "download_filter_pending" : "download_filter_ignore")
                            if viewModel.filter == filter { Label(label, systemImage: "checkmark") }
                            else { Text(label) }
                        }.accessibilityIdentifier("queue.filter." + filter)
                    }
                }
            }
        }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadDownloads()
            }
            await viewModel.checkNotifications()
        }
        .onDisappear {
            isAddingFocused = false
            viewModel.stopPolling()
        }
        .onChange(of: viewModel.filter) {
            Task { await viewModel.onFilterChanged() }
        }
    }

    private var queueControls: some View {
        HStack(spacing: 12) {
            Text(String(localized: viewModel.filter == "pending" ? "download_filter_pending" : "download_filter_ignore"))
                .font(.headline).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if authState.isPrivileged {
                if viewModel.downloadProgress.contains(where: { $0.canStop }) {
                    Button { Task { await viewModel.stopCurrentDownload() } } label: {
                        Label(String(localized: "queue_stop"), systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                    .accessibilityLabel(String(localized: "download_stop_button"))
                    .accessibilityIdentifier("queue.stop")
                } else {
                    Button { Task { await viewModel.startDownload() } } label: {
                        HStack(spacing: 6) {
                            if viewModel.isStartingDownload { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "arrow.down") }
                            Text(String(localized: "queue_start"))
                        }.font(.subheadline.weight(.semibold)).lineLimit(1).frame(minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(viewModel.isStartingDownload || viewModel.filter != "pending" || viewModel.items.isEmpty)
                    .accessibilityLabel(String(localized: "download_start_button"))
                    .accessibilityIdentifier("queue.start")
                }
                Button { Task { await viewModel.rescanSubscriptions() } } label: {
                    Group {
                        if viewModel.isRescanningSubscriptions { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }.frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless).disabled(viewModel.isRescanningSubscriptions)
                .accessibilityLabel(String(localized: "download_rescan_button"))
                .accessibilityIdentifier("queue.rescan")
            }
        }
    }

}

private struct DownloadItemRow: View {
    let item: DownloadItem
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AuthState.self) private var authState

    var body: some View {
        HStack(spacing: 12) {
            AuthenticatedAsyncImage(url: item.thumbUrl, fallbackURLs: ServerArtwork.videoFallbacks(item.youtubeId, baseURL: authState.serverURL ?? ""))
                .frame(width: typeSize.isAccessibilitySize ? 72 : 112, height: typeSize.isAccessibilitySize ? 72 : 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 3)

                Text(item.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !item.duration.isEmpty {
                        Text(item.duration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !item.published.isEmpty {
                        Text(item.published)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = item.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TaskNotificationBanner: View {
    let info: TaskNotification

    // Non-breaking space placeholder keeps the message row's height reserved (at the
    // same `.caption` text style) when there is no message to show.
    private var messageText: String {
        if let last = info.messages.last, !last.isEmpty {
            return last
        }
        return "\u{00A0}"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if info.isError {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(info.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if !info.isError {
                    Text("\(Int(info.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Always render the message row (using a non-breaking space placeholder
            // when empty) so the banner keeps a constant height tick-to-tick as
            // messages change. lineLimit(1) caps it to a single line.
            Text(messageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Always reserve the progress-bar row's vertical space. On error the bar
            // is hidden (but its space is kept) so toggling error state does not resize.
            ProgressView(value: info.isError ? 0 : info.progress)
                .tint(.blue)
                .opacity(info.isError ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }
}
