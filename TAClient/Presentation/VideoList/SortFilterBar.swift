import SwiftUI

enum SortOption: String, CaseIterable {
    case downloaded
    case published
    case views
    case likes
    case duration
    case mediasize

    var label: String {
        switch self {
        case .downloaded: return String(localized: "sort_downloaded")
        case .published: return String(localized: "sort_published")
        case .views: return String(localized: "sort_views")
        case .likes: return String(localized: "sort_likes")
        case .duration: return String(localized: "sort_duration")
        case .mediasize: return String(localized: "sort_mediasize")
        }
    }
}

enum WatchFilter: String, CaseIterable {
    case all
    case unwatched
    case watched
    case `continue`

    var label: String {
        switch self {
        case .all: return String(localized: "filter_all")
        case .unwatched: return String(localized: "filter_unwatched")
        case .watched: return String(localized: "filter_watched")
        case .continue: return String(localized: "filter_continue")
        }
    }

    var queryValue: String? {
        switch self {
        case .all: return nil
        case .unwatched: return "unwatched"
        case .watched: return "watched"
        case .continue: return "continue"
        }
    }
}

enum VidTypeFilter: String, CaseIterable {
    case all
    case videos
    case shorts
    case streams

    var label: String {
        switch self {
        case .all: return String(localized: "vid_type_all")
        case .videos: return String(localized: "vid_type_videos")
        case .shorts: return String(localized: "vid_type_shorts")
        case .streams: return String(localized: "vid_type_streams")
        }
    }

    var queryValue: String? {
        switch self {
        case .all: return nil
        case .videos: return "videos"
        case .shorts: return "shorts"
        case .streams: return "streams"
        }
    }
}

struct SortFilterMenu: View {
    @Binding var sortOption: SortOption
    @Binding var sortAscending: Bool
    @Binding var watchFilter: WatchFilter

    var body: some View {
        Menu {
            Section(String(localized: "sort_section_title")) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button { sortOption = option } label: {
                        if sortOption == option { Label(option.label, systemImage: "checkmark") }
                        else { Text(option.label) }
                    }
                    .accessibilityLabel(option.label)
                }
                Button { sortAscending.toggle() } label: {
                    Label(String(localized: sortAscending ? "sort_ascending" : "sort_descending"),
                          systemImage: sortAscending ? "arrow.up" : "arrow.down")
                }
                .accessibilityLabel(String(localized: sortAscending ? "sort_ascending" : "sort_descending"))
            }
            Section(String(localized: "filter_section_title")) {
                ForEach(WatchFilter.allCases, id: \.self) { filter in
                    Button { watchFilter = filter } label: {
                        if watchFilter == filter { Label(filter.label, systemImage: "checkmark") }
                        else { Text(filter.label) }
                    }
                    .accessibilityLabel(filter.label)
                }
            }
        } label: {
            Image(systemName: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(String(localized: "sort_filter_button"))
        .accessibilityValue(sortOption.label + ", " + watchFilter.label)
    }

    private var hasActiveFilters: Bool {
        sortOption != .downloaded || sortAscending || watchFilter != .unwatched
    }
}
