import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Child.createdAt) private var children: [Child]
    @AppStorage(DefaultsKey.currentChildID) private var currentChildID = ""
    @StateObject private var session = AppSession()

    private var activeChildren: [Child] {
        children.filter { !$0.isArchived }
    }

    var body: some View {
        Group {
            if activeChildren.isEmpty {
                ChildGateView()
            } else {
                MainTabView()
            }
        }
        .environmentObject(session)
        .tint(Theme.accent)
        .onAppear(perform: reconcileCurrentChild)
        .onChange(of: childToken) { _, _ in
            reconcileCurrentChild()
        }
        .onChange(of: currentChildID) { previous, next in
            guard !previous.isEmpty, previous != next else { return }
            clearDrafts()
        }
    }

    private var childToken: String {
        children.map { "\($0.id.uuidString):\($0.isArchived)" }.joined(separator: "|")
    }

    private func reconcileCurrentChild() {
        guard let current = ChildSelection.current(among: children, storedID: currentChildID) else {
            return
        }
        if currentChildID != current.id.uuidString {
            currentChildID = current.id.uuidString
        }
    }

    private func clearDrafts() {
        let removed = (try? JobPipeline.clearDrafts(context: context)) ?? 0
        if removed > 0 {
            session.notice = "已清除 \(removed) 份尚未生成题目卡片的上传草稿。"
        }
    }
}

enum ChildSelection {
    static func current(among children: [Child], storedID: String) -> Child? {
        let active = children.filter { !$0.isArchived }.sorted { $0.createdAt < $1.createdAt }
        if let match = active.first(where: { $0.id.uuidString == storedID }) {
            return match
        }
        return active.first
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
            WrongBookView()
                .tabItem { Label("错题本", systemImage: "book.closed") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
