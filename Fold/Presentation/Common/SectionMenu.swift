import SwiftUI

/// Primary sections expose one menu: Settings and their supported filters.
struct SectionMenu<Filters: View>: View {
    @Environment(AppRouter.self) private var router
    var hasFilters = true
    @ViewBuilder var filters: () -> Filters
    var body: some View {
        Menu {
            Button { router.navigate(to: .settings) } label: {
                Label(String(localized: "settings_title"), systemImage: "gearshape")
            }.accessibilityIdentifier("section.settings")
            if hasFilters {
                Menu { filters() } label: {
                    Label(String(localized: "nav_filters"), systemImage: "line.3.horizontal.decrease")
                }.accessibilityIdentifier("section.filters")
            }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
        .accessibilityLabel(String(localized: "more_actions"))
        .accessibilityIdentifier("section.menu")
    }
}

struct LibraryFilterActions: View {
    @Bindable var viewModel: VideoListViewModel
    var body: some View {
        Section(String(localized: "vid_type_section_title")) {
            ForEach(VidTypeFilter.allCases, id: \.self) { type in
                Button { viewModel.setVidType(type) } label: {
                    if viewModel.vidTypeFilter == type { Label(type.label, systemImage: "checkmark") }
                    else { Text(type.label) }
                }.accessibilityIdentifier("library.filter.type." + type.rawValue)
            }
        }
        Section(String(localized: "filter_section_title")) {
            ForEach(WatchFilter.allCases, id: \.self) { filter in
                Button { viewModel.watchFilter = filter } label: {
                    if viewModel.watchFilter == filter { Label(filter.label, systemImage: "checkmark") }
                    else { Text(filter.label) }
                }.accessibilityIdentifier("library.filter.watch." + filter.rawValue)
            }
        }
        Section(String(localized: "sort_section_title")) {
            ForEach(SortOption.allCases, id: \.self) { sort in
                Button { viewModel.sortOption = sort } label: {
                    if viewModel.sortOption == sort { Label(sort.label, systemImage: "checkmark") }
                    else { Text(sort.label) }
                }.accessibilityIdentifier("library.filter.sort." + sort.rawValue)
            }
            Button { viewModel.sortAscending.toggle() } label: {
                Label(String(localized: viewModel.sortAscending ? "sort_ascending" : "sort_descending"),
                      systemImage: viewModel.sortAscending ? "arrow.up" : "arrow.down")
            }
        }
    }
}
