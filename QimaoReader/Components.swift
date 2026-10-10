import SwiftUI

/// 封面(带占位)
struct CoverImage: View {
    let url: String
    var corner: CGFloat = 6

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                ZStack {
                    Color(red: 0.95, green: 0.93, blue: 0.90)
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.gray.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .cornerRadius(corner)
    }
}

/// 小标签(橙色浅底)
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(QTheme.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(QTheme.primarySoft)
            .cornerRadius(5)
    }
}
