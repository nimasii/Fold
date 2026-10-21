import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            FoldWordmark()
            Text(String(localized: "cinema_tagline")).font(.subheadline).foregroundStyle(.secondary)

            ProgressView()
                .controlSize(.regular)

            Spacer()
        }.frame(maxWidth: .infinity).background(StreamingStyle.background)
    }
}
