import SwiftUI

/// 이 달과 지난달의 **누적 지출**을 겹쳐 그린 선 그래프.
///
/// 두 크기로 산다.
///
/// - `inline` — 요약 밴드의 "지난달보다 얼마 더 썼어요" 옆. 문장이 말하는 차이를
///   눈으로 보여준다. 문장은 결과만 말하고 그래프는 **언제 벌어졌는지**를 말한다.
/// - `expanded` — 분석 화면(`SpendingDetailView`)의 큰 그래프. 같은 그림을 키우고
///   가로 끝에 첫날·말일을 붙인다.
///
/// **한 벌로 그린다.** 밴드와 분석 화면이 같은 두 선을 다르게 그리면, 작은 그래프를
/// 눌러 큰 그래프를 열었을 때 같은 것이라는 게 안 읽힌다.
///
/// 축도 눈금도 격자도 그리지 않는다 — 참조 시스템의 차트 규칙이 그렇고, 읽어야
/// 하는 건 두 선의 벌어짐이지 값이 아니다. 큰 쪽에서 가로 끝 날짜만 예외인데,
/// 그건 눈금이 아니라 **이 선이 한 달치라는 것**을 말하는 라벨이다.
struct SpendingSparkline: View {

    /// 그래프가 놓이는 자리.
    enum Scale {
        /// 요약 밴드에 붙는 작은 그래프. 라벨이 없다.
        case inline
        /// 분석 화면의 큰 그래프. 가로 끝에 첫날·말일이 붙는다.
        case expanded(start: String, end: String)
    }

    /// 이 달 누적 지출 (1일부터 하루씩).
    let current: [Int]
    /// 지난달 누적 지출.
    let previous: [Int]
    /// 이 달 선의 색. **지난달보다 더 썼으면 빨강, 덜 썼으면 파랑**이라
    /// 바로 옆 문장의 금액과 같은 색으로 묶인다.
    let tint: Color
    var scale: Scale = .inline

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

    private var isExpanded: Bool {
        if case .expanded = scale { return true }
        return false
    }

    var body: some View {
        switch scale {
        case .inline:
            canvas
                .frame(width: DS.Spacing.s20 + DS.Spacing.s4, height: DS.Spacing.s16)
                .accessibilityHidden(true)

        case let .expanded(start, end):
            VStack(spacing: DS.Spacing.small) {
                canvas.frame(height: DS.Size.chart)
                HStack {
                    Text(start)
                    Spacer()
                    Text(end)
                }
                .typeStyle(DS.Typo.captionS)
                .foregroundColor(DS.Ink.tertiary)
                .tabularAmount()
            }
            // 그래프가 말하는 것은 바로 위 문장이 이미 말하고 있다.
            .accessibilityHidden(true)
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            // 큰 그래프에서만 지난달 선 아래를 옅게 채운다. 작은 자리에서는 면이
            // 선을 삼켜서 두 선의 벌어짐이 안 읽힌다.
            if isExpanded, previous.count > 1 {
                context.fill(area(previous, in: size), with: .color(DS.Surface.secondary))
            }
            if previous.count > 1 {
                context.stroke(
                    path(previous, in: size),
                    with: .color(DS.Line.strong),
                    style: .init(lineWidth: isExpanded ? 2 : 1.5, lineCap: .round, lineJoin: .round)
                )
            }
            guard current.count > 1 else { return }
            context.stroke(
                path(current, in: size),
                with: .color(tint),
                style: .init(lineWidth: isExpanded ? 3 : 2.5, lineCap: .round, lineJoin: .round)
            )
            // 이 달 선의 끝에 점 하나. "여기까지 왔다" 를 말한다.
            // 옅은 테를 한 겹 두른다 — 점만 찍으면 선의 일부로 읽혀서 끝인 줄 모른다.
            let tip = point(index: current.count - 1, value: current[current.count - 1], in: size)
            let halo = dot * 2
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - halo, y: tip.y - halo, width: halo * 2, height: halo * 2)),
                with: .color(tint.opacity(0.18))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - dot, y: tip.y - dot, width: dot * 2, height: dot * 2)),
                with: .color(tint)
            )
        }
    }

    /// 끝점의 반지름. 테까지 상자 안에 들어와야 해서 위아래 여백을 이 값이 정한다.
    private var dot: CGFloat { isExpanded ? 5 : 3.5 }

    /// 위아래로 남기는 여백. 끝점의 테(반지름의 두 배)만큼은 있어야 안 잘린다.
    private var inset: CGFloat { max(8, dot * 2) }

    private func path(_ values: [Int], in size: CGSize) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            let p = point(index: index, value: value, in: size)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// 선 아래를 채우는 면. 선을 그대로 따라가다 바닥으로 떨어뜨려 닫는다.
    private func area(_ values: [Int], in size: CGSize) -> Path {
        var path = self.path(values, in: size)
        guard let last = values.indices.last else { return path }
        let end = point(index: last, value: values[last], in: size)
        let start = point(index: 0, value: values[0], in: size)
        path.addLine(to: CGPoint(x: end.x, y: size.height))
        path.addLine(to: CGPoint(x: start.x, y: size.height))
        path.closeSubpath()
        return path
    }

    private func point(index: Int, value: Int, in size: CGSize) -> CGPoint {
        let x = size.width * CGFloat(index) / CGFloat(span - 1)
        let ratio = CGFloat(value) / CGFloat(ceiling)
        let y = size.height - inset - ratio * (size.height - inset * 2)
        return CGPoint(x: min(max(x, inset), size.width - inset), y: y)
    }
}
