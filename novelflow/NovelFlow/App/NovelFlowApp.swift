import SwiftUI
import SwiftData

@main
struct NovelFlowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [ShelfBook.self, ReadingPosition.self, Bookmark.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ShelfView()
            }
            .tabItem { Label("书架", systemImage: "books.vertical") }
            .tag(0)

            NavigationStack {
                DiscoverView()
            }
            .tabItem { Label("书库", systemImage: "sparkles") }
            .tag(1)

            NavigationStack {
                TypesettingLabView()
            }
            .tabItem { Label("排版实验室", systemImage: "textformat.size") }
            .tag(2)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label("关于", systemImage: "info.circle") }
            .tag(3)
        }
        .tint(NFTheme.accent)
        .onAppear {
            DownloadManager.shared.attach(context: modelContext)
            ChapterCacheManager.shared.attach(context: modelContext)
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NovelFlow")
                        .font(.title2.weight(.semibold))
                    Text("安静、耐用的小说阅读器")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("当前版本状态") {
                LabeledContent("版本", value: "0.3.0(P6:全网书源)")
                LabeledContent("阅读引擎", value: "分页 / 滚动双模式 · 锚点恢复")
                LabeledContent("阅读工具", value: "书签 / 全文搜索 / 点按分区")
                LabeledContent("本地导入", value: "TXT / EPUB 已接通")
                LabeledContent("全网书源", value: "七猫 / 番茄 / 起点 + 开放书库")
                LabeledContent("整本缓存", value: "逐章抓取 / 断点续传 / 离线阅读")
            }
            Section("来源与许可") {
                Text("开放书库内容依据 Project Gutenberg 许可提供。中文书源(七猫 / 番茄 / 起点)通过其公开网页与公开接口获取书籍信息与章节内容,仅供个人阅读使用;如内容涉及订阅章节,请前往来源 App 支持作者。本地文件仅在设备上处理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("书签、全文搜索与滚动阅读已交付;继续打磨阅读细节与更多书源。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于")
    }
}
