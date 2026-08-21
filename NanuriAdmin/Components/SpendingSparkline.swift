import SwiftUI

/// 이 달과 지난달의 **누적 지출**을 겹쳐 그린 작은 선 그래프.
///
/// 요약 밴드의 "지난달보다 얼마 더 썼어요" 옆에 붙어, 그 한 문장이 말하는 차이를
/// 눈으로 보여준다. 문장은 결과만 말하고 그래프는 **언제 벌어졌는지**를 말한다.
///
/// 축도 눈금도 격자도 그리지 않는다 — 참조 시스템의 차트 규칙이 그렇고,
/// 이만한 크기에서는 선 말고 아무것도 읽히지 않는다. 읽어야 하는 건 두 선의
/// 벌어짐이지 값이 아니다.
struct SpendingSparkline: View {
    /// 이 달 누적 지출 (1일부터 하루씩).
    let current: [Int]
    /// 지난달 누적 지출.
    let previous: [Int]
    /// 이 달 선의 색. **지난달보다 더 썼으면 빨강, 덜 썼으면 파랑**이라
    /// 바로 옆 문장의 금액과 같은 색으로 묶인다.
    let tint: Color

    /// 두 선이 같은 자를 쓰게 만드는 최댓값. 각자 정규화하면 더 쓴 달이
    /// 오히려 낮아 보이는 거짓말이 된다.
    private var ceiling: Int {
        max(current.last ?? 0, previous.last ?? 0, 1)
    }

    /// 가로축은 **긴 달 기준**이다. 짧은 달을 늘려 맞추면 같은 날짜가 다른
    /// 자리에 놓여 두 선을 견줄 수 없다.
    private var span: Int {
        max(current.count, previous.count, 2)
    }

    var body: some View {
        Canvas { context, size in
            if previous.count > 1 {
                context.stroke(
                    path(previous, in: size),
                    with: .color(DS.Line.strong),
                    style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
            guard current.count > 1 else { return }
            context.stroke(
                path(current, in: size),
                with: .color(tint),
                style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            // 이 달 선의 끝에 점 하나. "여기까지 왔다" 를 말한다.
            // 옅은 테를 한 겹 두른다 — 점만 찍으면 선의 일부로 읽혀서 끝인 줄 모른다.
            let tip = point(index: current.count - 1, value: current[current.count - 1], in: size)
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - 7, y: tip.y - 7, width: 14, height: 14)),
                with: .color(tint.opacity(0.18))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7)),
                with: .color(tint)
            )
        }
        .frame(width: DS.Spacing.s20 + DS.Spacing.s4, height: DS.Spacing.s16)
        .accessibilityHidden(true)
    }

    private func path(_ values: [Int], in size: CGSize) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            let p = point(index: index, value: value, in: size)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// 위아래로 8pt 씩 남긴다 — 끝점의 테까지 상자 안에 들어와야 안 잘린다.
    private func point(index: Int, value: Int, in size: CGSize) -> CGPoint {
        let inset: CGFloat = 8
        let x = size.width * CGFloat(index) / CGFloat(span - 1)
        let ratio = CGFloat(value) / CGFloat(ceiling)
        let y = size.height - inset - ratio * (size.height - inset * 2)
        return CGPoint(x: min(max(x, inset), size.width - inset), y: y)
    }
}
