import SwiftUI
import SwiftData

struct MainTabView: View {
    enum Tab: Hashable {
        case transactions
        case record
        case statistics
    }

    @State private var selectedTab: Tab = .transactions

    var body: some View {
        TabView(selection: $selectedTab) {
            TransactionListView()
                .tabItem { Label("流水", systemImage: "list.bullet.rectangle.portrait") }
                .tag(Tab.transactions)

            RecordView(selectedTab: $selectedTab)
                .tabItem { Label("记一笔", systemImage: "plus.circle.fill") }
                .tag(Tab.record)

            StatisticsView()
                .tabItem { Label("统计", systemImage: "chart.pie.fill") }
                .tag(Tab.statistics)
        }
        .tint(.brand)
    }
}

#Preview {
    MainTabView()
        .modelContainer(ModelContainerProvider.preview)
}
