import SwiftUI

/// 书架(P0 空状态;P1 起接入本地导入的真实书籍)
struct ShelfView: View {
    var body: some View {
        ContentUnavailableView {
            Label("书架空空如也", systemImage: "books.vertical")
        } description: {
            Text("本地导入(TXT / EPUB)将在下一阶段接入,导入后的书籍会出现在这里。")
        }
        .background(NFTheme.background)
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.inline)
    }
}
