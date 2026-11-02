import BrushCore
import SwiftUI

/// "Mit tud az app?": swipeable feature tour, after the first setup and from Settings.
struct TourView: View {
    let onDone: () -> Void
    @State private var page = 0
    private let pages = Tour.pages(platform: .ios)

    var body: some View {
        let last = page == pages.count - 1
        VStack(spacing: 0) {
            HStack {
                Text(tr("Mit tud az app?")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !last { Button(tr("Kihagyás"), action: onDone) }
            }
            .padding(.horizontal, 24).padding(.top, 16)
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { item in
                    VStack(spacing: 20) {
                        Text(item.element.icon)
                            .font(.system(size: 76))
                            .frame(width: 150, height: 150)
                            .background(Circle().fill(Color(.systemBackground)))
                            .accessibilityHidden(true)
                        Text(item.element.title).font(.title.bold()).multilineTextAlignment(.center)
                        Text(item.element.text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .tag(item.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if last { onDone() } else { withAnimation { page += 1 } }
            } label: {
                Text(last ? tr("Kezdjük!") : tr("Tovább")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(24)
        }
        .background(LinearGradient(colors: [Theme.kidTop, Theme.kidBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}
