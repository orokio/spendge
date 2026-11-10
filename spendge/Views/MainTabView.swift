import SwiftUI
import SwiftData

struct MainTabView: View {
    enum Tab: Hashable {
        case home
        case record
        case review
    }

    @State private var selectedTab: Tab = .home // .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("今天", systemImage: "sun.max") }
                .tag(Tab.home)

            RecordView(selectedTab: $selectedTab)
                .tabItem { Label("记一笔", systemImage: "plus.circle.fill") }
                .tag(Tab.record)

            ReviewView()
                .tabItem { Label("回看", systemImage: "chart.bar.doc.horizontal") }
                .tag(Tab.review)
        }
        .tint(.brand)
    }
}

#Preview {
    MainTabView()
        .modelContainer(ModelContainerProvider.preview)
}
