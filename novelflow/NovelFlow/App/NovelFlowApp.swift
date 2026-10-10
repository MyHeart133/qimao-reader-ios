import SwiftUI
import SwiftData

@main
struct NovelFlowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [ShelfBook.self, ReadingPosition.self])
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
                LabeledContent("版本", value: "0.1.0（P0+P1）")
                LabeledContent("阅读引擎", value: "章节解析 / 分页 / 锚点恢复 已就绪")
                LabeledContent("本地导入", value: "TXT / EPUB 已接通")
                LabeledContent("开放书库", value: "Gutenberg 已接入")
                LabeledContent("下载管理", value: "基础下载可用(P3 完善)")
            }
            Section("来源与许可") {
                Text("Gutenberg 书源内容为公共领域作品,依据 Project Gutenberg 许可提供下载与离线阅读。本地文件仅在设备上处理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("本项目按路线图持续推进:书签/全文搜索/下载中心/更多合法书源在后续阶段交付。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于")
    }
}
