import SwiftUI

/// 프로필 사진 원. 주소가 없으면 기본 아이콘이 들어온다.
///
/// 이미지 로딩은 `RemoteImage`(Kingfisher) 가 한다 — 예전에는 이 파일이 자기 캐시를
/// 따로 들고 있었다. 기본 `AsyncImage` 가 재렌더마다 다시 받아서 사진이 안 뜨던
/// 문제 때문이었는데, 영수증도 같은 문제를 겪어서 로더를 공용으로 옮겼다.
struct AvatarView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                RemoteImage(url: parsed, maxDimension: size) {
                    AvatarView.defaultIcon
                } failure: {
                    AvatarView.defaultIcon
                }
                .scaledToFill()
            } else {
                AvatarView.defaultIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    static var defaultIcon: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundColor(DS.Ink.disabled)
    }
}
