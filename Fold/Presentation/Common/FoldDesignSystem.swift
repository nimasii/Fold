import SwiftUI

/// Glass is restricted to controls. Artwork and reading surfaces stay opaque.
struct FoldGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: 12) { content() } }
        else { content() }
    }
}

private struct FoldActionModifier: ViewModifier {
    let prominent: Bool
    let shape: ButtonBorderShape
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
            if prominent {
                content.buttonStyle(.glassProminent).tint(.white).foregroundStyle(isEnabled ? Color.black : Color.primary)
                    .controlSize(.large).buttonBorderShape(shape)
            } else {
                content.buttonStyle(.glass).tint(.primary).foregroundStyle(.primary).controlSize(.large).buttonBorderShape(shape)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(isEnabled ? Color.black : Color.primary)
                .controlSize(.large).buttonBorderShape(shape)
        } else {
            content.buttonStyle(.bordered).tint(.primary).controlSize(.large).buttonBorderShape(shape)
        }
    }
}

extension View {
    func foldAction(prominent: Bool = false, shape: ButtonBorderShape = .roundedRectangle(radius: 12)) -> some View {
        modifier(FoldActionModifier(prominent: prominent, shape: shape))
    }
    @ViewBuilder func foldReadingSurface() -> some View {
        if #available(iOS 26, *) {
            scrollContentBackground(.hidden).background(StreamingStyle.background)
                .listRowBackground(StreamingStyle.surface)
                .scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            scrollContentBackground(.hidden).background(StreamingStyle.background)
                .listRowBackground(StreamingStyle.surface)
        }
    }
}

struct FoldWordmark: View {
    var font: Font = .largeTitle
    var body: some View {
        (Text("fold").foregroundStyle(.primary) + Text(".").foregroundStyle(StreamingStyle.accent))
            .font(font.weight(.bold)).tracking(-1)
            .accessibilityLabel("Fold")
    }
}

struct CinemaIntroduction: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            Text(title).font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared horizontal identity for queue, collections and related videos.
struct CinemaVideoRow: View {
    let video: Video
    var localArtwork: LocalVideoArtwork? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                .overlay { AuthenticatedAsyncImage(url: video.thumbUrl, localFileURL: localArtwork?.thumbnail, localRevision: localArtwork?.revision ?? 0) }
                .frame(width: 112).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(video.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(video.channelName).font(.caption).foregroundStyle(.secondary)
                Text(video.durationStr).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 64).contentShape(Rectangle())
    }
}

private struct FoldControlSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else { content.background(StreamingStyle.elevated, in: .rect(cornerRadius: 18)) }
    }
}

extension View {
    func foldControlSurface() -> some View { modifier(FoldControlSurface()) }
}
