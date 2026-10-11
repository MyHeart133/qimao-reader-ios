import SwiftUI

/// 书库结果卡片
struct SourceBookCard: View {
    let book: SourceBook

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: book.cover ?? "")) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    ZStack {
                        NFTheme.accentSoft
                        Image(systemName: "book.closed.fill").foregroundStyle(NFTheme.accent.opacity(0.5))
                    }
                }
            }
            .frame(width: 60, height: 84)
            .clipped()
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NFTheme.textPrimary)
                    .lineLimit(2)
                Text(book.author.isEmpty ? "未知作者" : book.author)
                    .font(.system(size: 13))
                    .foregroundStyle(NFTheme.textSecondary)
                    .lineLimit(1)
                if let s = book.summary, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundStyle(NFTheme.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let src = SourceRegistry.shared.source(withID: book.sourceID) {
                        chip(src.displayName)
                        if book.downloadURL == nil && src.capabilities.onlineReading {
                            chip("可缓存全本")
                        }
                    }
                    if let lang = book.language {
                        chip(lang.uppercased())
                    }
                    if let fmt = book.downloadFormat {
                        chip(fmt.uppercased() + " 可下载")
                    }
                    if let dl = book.downloadCount, dl > 0 {
                        chip("↓\(dl)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(NFTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(NFTheme.accentSoft)
            .cornerRadius(4)
    }
}
