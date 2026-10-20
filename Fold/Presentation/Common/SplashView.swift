import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("FoldMark")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            ProgressView()
                .controlSize(.regular)

            Spacer()
        }
    }
}
