import SwiftUI

/// **장부 한 줄.**
///
/// **금액이 제목 자리다.** 왼쪽 첫 줄에 크고 굵게 오고, 무엇에 쓴 돈인지는
/// 그 아래 회색 부제로 붙는다. 제목이 왼쪽·금액이 오른쪽이던 적이 있는데,
/// 장부를 훑을 때 눈이 먼저 잡는 건 결국 수다.
///
/// **거래가 아니라 조각을 그린다.** 묶어 보낸 출금 하나는 여기서 여러 줄이 된다 —
/// 사람이 쓰던 엑셀이 그 모양이고, 보고서·분석도 이미 그 단위로 센다.
///
/// 시각은 뺐다 — 날짜는 섹션 머리가 말하고, 몇 시였는지는 훑을 때 필요한 정보가
/// 아니다. 상세 시트의 "일시" 에 그대로 있다.
struct LedgerRowView: View {
    let row: LedgerRow
    /// 고르는 중일 때만 값이 있다. `nil` 이면 평소 목록이다.
    var isSelected: Bool?
    /// 이 항목의 카테고리에 정해 둔 아이콘 `id`. 없으면 `nil` — 왼쪽 타일을 안 그린다.
    /// (매칭 결과 화면의 썸네일 문법을 재정 목록에 들여온 것이다.)
    var iconId: String?

    var body: some View {
        HStack(spacing: DS.Spacing.medium) {
            if let isSelected {
                // 청구서 탭 선택 모드와 같은 표식이다. 고르는 중엔 왼쪽 자리가
                // 체크 것이라 아이콘 타일은 안 그린다 — 왼쪽에 둘을 겹치지 않는다.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(DS.Icon.font(DS.Icon.action))
                    .foregroundColor(isSelected ? DS.Palette.accent : DS.Ink.placeholder)
            } else if let iconId {
                iconTile(iconId)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.s4)
        .padding(.vertical, DS.Spacing.medium)
    }

    /// 왼쪽 카테고리 아이콘 타일. 매칭 결과 행의 썸네일과 같은 크기·모서리다
    /// (`DS.Size.rowAvatar`, `DS.Radius.m`). 색은 뜻을 타지 않는다 — 카테고리 표식일
    /// 뿐이라 입금 파랑·출금 검정을 빌리지 않고 본문색으로 둔다(§5).
    private func iconTile(_ id: String) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.m)
            .fill(DS.Surface.secondary)
            .overlay(
                CategoryIconImage(iconId: id)
                    .frame(width: DS.Icon.feature, height: DS.Icon.feature)
                    .foregroundColor(DS.Ink.primary)
            )
            .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
            // 입금은 브랜드 파랑, 출금은 본문 검정이다. 장부에서 지출은 사고가
            // 아니라 일상이라 경고색을 주지 않는다.
            //
            // **통장 사이 이체는 셋째 색이다.** 수입도 지출도 아니라서 — 장부
            // 전체로 보면 나간 돈도 들어온 돈도 아니고 합계·보고서에서도 빠진다.
            // 파랑이나 검정을 주면 그 줄이 다른 줄과 같은 종류의 수로 읽힌다.
            Text(row.isDeposit
                 ? "+\(row.amount.formatted())원"
                 : "\(row.amount.formatted())원")
                .typeStyle(DS.Typo.title2)
                .tabularAmount()
                .foregroundColor(amountColor)
                .lineLimit(1)

            Text(subtitle)
                .typeStyle(DS.Typo.body2)
                .foregroundColor(DS.Ink.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 금액의 색. 입금 파랑 · 출금 검정 · **통장 사이 이체는 회색**이다.
    private var amountColor: Color {
        if row.isInternalTransfer { return DS.Ink.tertiary }
        return row.isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal
    }

    /// 금액 아래 한 줄. **장부 적요 · 카테고리** 순이다.
    ///
    /// 은행이 찍은 적요를 앞에 두던 적이 있는데(`홍길동 · 볼링 게임 우승 상품`),
    /// 그건 **장부를 훑는 사람이 알고 싶은 순서가 아니다.** 이 목록은 통장이 아니라
    /// 장부고, 장부에 적힌 이름이 먼저 와야 한다. 은행 적요는 상세에 있다.
    ///
    /// **카테고리가 비면 가운뎃점째로 안 나온다.** 거래내역서로 들어온 조각은
    /// 카테고리가 비어 있는데, 거기에 "미지정" 을 적으면 목록이 그 글자로 뒤덮인다.
    private var subtitle: String {
        // 내부 이체에는 분할 항목이 없다. 대신 성격을 말한다.
        if row.isInternalTransfer { return "통장 사이 이체" }
        let head = clean(row.title) ?? "-"
        guard let tail = clean(row.category) else { return head }
        return "\(head) · \(tail)"
    }

    private func clean(_ value: String?) -> String? {
        let v = value?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? nil : v
    }
}
