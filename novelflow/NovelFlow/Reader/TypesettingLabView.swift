import SwiftUI
import UIKit

/// 排版实验室:分页引擎的活体验证台
/// - 实时调整字号 / 行距 / 段距 / 页边距 / 字体 / 主题
/// - 每次重排保持阅读位置(锚点),与读者视角一致
@MainActor
final class TypesettingLabModel: ObservableObject {
    let sampleText: String

    @Published var typography = ReaderTypography()
    @Published var themeIndex = 0
    @Published private(set) var pages: [PageSlice] = []
    @Published private(set) var pageIndex = 0
    @Published private(set) var pagingMillis: Double = 0
    @Published private(set) var totalCharacters: Int = 0
    @Published private(set) var paging = false

    private var anchorOffset = 0
    private var lastSize: CGSize = .zero
    private var generation = 0
    private var pendingTask: Task<Void, Never>?

    init() {
        sampleText = SampleText.chineseNovel
        totalCharacters = (sampleText as NSString).length
    }

    var pageCount: Int { pages.count }

    var currentPage: PageSlice? {
        guard pageIndex >= 0, pageIndex < pages.count else { return nil }
        return pages[pageIndex]
    }

    var progress: Double {
        guard !pages.isEmpty else { return 0 }
        return Double(pageIndex + 1) / Double(pages.count)
    }

    /// 120ms 防抖:滑块连续拖动时不产生分页风暴
    func scheduleRepaginate() {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.repaginate(keepAnchor: true)
        }
    }

    func repaginate(size: CGSize? = nil, keepAnchor: Bool = true) {
        if let s = size, s.width > 1, s.height > 1 {
            lastSize = s
        }
        let contentSize = CGSize(
            width: lastSize.width - typography.horizontalMargin * 2,
            height: lastSize.height - typography.verticalMargin * 2
        )
        guard contentSize.width > 40, contentSize.height > 40 else { return }

        if keepAnchor, let p = currentPage {
            anchorOffset = p.location
        }
        let capturedAnchor = anchorOffset
        generation += 1
        let gen = generation
        let text = sampleText
        let typo = typography
        paging = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (PaginationResult, Double) in
                let t0 = CFAbsoluteTimeGetCurrent()
                let result = PaginationEngine.paginate(text: text, typography: typo, pageSize: contentSize)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                return (result, ms)
            }.value

            guard gen == self.generation else { return } // 过期结果丢弃
            self.pages = outcome.0.pages
            self.pagingMillis = outcome.1
            self.totalCharacters = outcome.0.sourceLength
            if keepAnchor {
                self.pageIndex = PaginationEngine.pageIndex(containing: capturedAnchor, in: outcome.0) ?? 0
            } else {
                self.pageIndex = min(self.pageIndex, max(0, outcome.0.pages.count - 1))
            }
            self.paging = false
        }
    }

    func nextPage() {
        guard pageIndex + 1 < pages.count else { return }
        pageIndex += 1
        if let p = currentPage { anchorOffset = p.location }
    }

    func prevPage() {
        guard pageIndex > 0 else { return }
        pageIndex -= 1
        if let p = currentPage { anchorOffset = p.location }
    }
}

// MARK: - 页面

struct TypesettingLabView: View {
    @StateObject private var model = TypesettingLabModel()
    @State private var showSettings = false

    private var theme: ReaderTheme { ReaderTheme.theme(model.themeIndex) }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            readerArea
            controlBar
            if showSettings {
                SettingsPanel(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(NFTheme.background)
        .navigationTitle("排版实验室")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .onChange(of: model.typography) { _, _ in
            model.scheduleRepaginate()
        }
        .onChange(of: model.themeIndex) { _, _ in
            // 主题只影响绘制,不触发重排
        }
    }

    private var statsBar: some View {
        HStack(spacing: 12) {
            Text("页 \(model.pageCount == 0 ? 0 : model.pageIndex + 1)/\(model.pageCount)")
            Text("·")
            Text("分页 \(model.pagingMillis, specifier: "%.1f") ms")
            Text("·")
            Text("\(model.totalCharacters) 字")
            if model.paging {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(NFTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(NFTheme.surface.opacity(0.6))
    }

    private var readerArea: some View {
        GeometryReader { geo in
            ZStack {
                theme.background
                if let page = model.currentPage {
                    ReaderPageView(
                        attributed: PaginationEngine.attributedText(
                            model.sampleText,
                            typography: model.typography,
                            textColor: theme.uiText
                        ),
                        pageRange: page.range,
                        contentInsets: UIEdgeInsets(
                            top: model.typography.verticalMargin,
                            left: model.typography.horizontalMargin,
                            bottom: model.typography.verticalMargin,
                            right: model.typography.horizontalMargin
                        ),
                        backgroundColor: theme.uiBackground
                    )
                } else {
                    ProgressView("正在排版…")
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                model.repaginate(size: geo.size, keepAnchor: false)
            }
            .onChange(of: geo.size) { _, newSize in
                model.repaginate(size: newSize, keepAnchor: true)
            }
        }
    }

    private var controlBar: some View {
        HStack {
            Button {
                model.prevPage()
            } label: {
                Label("上一页", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 56, height: 40)
            }
            .disabled(model.pageIndex <= 0)

            Spacer()

            Text("\(model.pageCount == 0 ? 0 : model.pageIndex + 1) / \(model.pageCount)")
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(NFTheme.textPrimary)

            Spacer()

            Button {
                model.nextPage()
            } label: {
                Label("下一页", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 56, height: 40)
            }
            .disabled(model.pageIndex + 1 >= model.pageCount)

            Spacer()

            Button {
                showSettings.toggle()
            } label: {
                Label("排版设置", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 56, height: 40)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(NFTheme.surface)
    }
}

// MARK: - 设置面板(inline,不遮挡正文上半部分)

struct SettingsPanel: View {
    @ObservedObject var model: TypesettingLabModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("字号")
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
                Spacer()
                Button {
                    model.typography.fontSize = max(13, model.typography.fontSize - 1)
                } label: {
                    Text("A-")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 44, height: 32)
                }
                Text("\(Int(model.typography.fontSize))")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .frame(width: 36)
                Button {
                    model.typography.fontSize = min(28, model.typography.fontSize + 1)
                } label: {
                    Text("A+")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 44, height: 32)
                }
            }
            .tint(NFTheme.accent)

            sliderRow("行距", value: $model.typography.lineSpacing, range: 2...20)
            sliderRow("段距", value: $model.typography.paragraphSpacing, range: 0...30)
            sliderRow("页边距", value: $model.typography.horizontalMargin, range: 12...40)

            Picker("字体", selection: $model.typography.fontName) {
                ForEach(ReaderTypography.fontChoices, id: \.name) { choice in
                    Text(choice.display).tag(choice.name)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                Text("主题")
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
                Spacer()
                ForEach(ReaderTheme.all) { t in
                    ZStack {
                        Circle()
                            .fill(t.background)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(NFTheme.separator, lineWidth: 1))
                        if model.themeIndex == t.id {
                            Circle()
                                .stroke(NFTheme.accent, lineWidth: 2.5)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .onTapGesture { model.themeIndex = t.id }
                }
            }
        }
        .padding(16)
        .background(NFTheme.surface)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func sliderRow(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(NFTheme.textSecondary)
                .frame(width: 48, alignment: .leading)
            Slider(value: value, in: range)
                .tint(NFTheme.accent)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(NFTheme.textSecondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - 占位:导入样例(在未接真实导入前,实验室提供"读样例"入口已由实验室覆盖)

struct ShelfPlaceholderNote: View {
    var body: some View {
        EmptyView()
    }
}
