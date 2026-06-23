import SwiftUI

struct AvatarView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        defaultIcon
                    }
                }
            } else {
                defaultIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var defaultIcon: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundColor(Color(.systemGray3))
    }
}
