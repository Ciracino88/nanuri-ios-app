import SwiftUI

/// 헤더 햄버거(≡)가 여는 메뉴가 고를 수 있는 동작.
///
/// 실행 자체는 `FinanceView.runPendingMenuAction` 이 갖는다 — 내보내기 진행
/// 오버레이·공유 시트가 그쪽에 있어서, 메뉴는 갈래만 고른다.
enum FinanceMenuAction {
    case accounts
    case reportPreview
    case exportReportPDF
    case exportReceiptsPDF
}

/// 헤더 햄버거가 여는 **풀스크린 메뉴.**
///
/// 예전에는 `⋯` 드롭다운이었다. 인스타그램 프로필의 ≡ 처럼 화면을 통째로 덮는
/// 메뉴로 바꿨다 — 항목마다 아이콘·설명이 붙어 드롭다운보다 읽기 쉽고, 앞으로
/// 늘어날 자리도 넉넉하다.
///
/// **행은 프로필 탭의 `actionRow` 와 같은 문법이다** — 아이콘 + 라벨 + 셰브론이
/// 카드 위에 앉는다. 훑는 목록이 아니라 **저마다 독립된 동작**이라 섹션이 아니라
/// 카드다 (DESIGN.md 1번의 카드/섹션 표).
///
/// 동작은 직접 하지 않고 `onSelect` 로 갈래만 넘긴다. 부모가 메뉴를 닫고 실행한다.
struct FinanceMenuView: View {
    /// 이 달에 내보낼 거래가 있는가. 없으면 내보내기 줄을 흐리게 잠근다.
    let hasData: Bool
    let onSelect: (FinanceMenuAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 인스타그램 설정처럼 왼쪽 뒤로가기 + 가운데 제목이다. 알림 종은 끈다.
            AdminHeaderView(
                showsNotifications: false,
                center: { Text("메뉴").headerTitle() },
                leading: {
                    HeaderBackButton(label: "닫기") { dismiss() }
                },
                trailing: { EmptyView() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    // 통장은 늘 보는 수가 아니라 가끔 확인하는 수라 여기 모였다.
                    menuGroup(title: "통장") {
                        menuRow(icon: "wallet.bifold", label: "통장 잔액",
                                tint: DS.Ink.primary, enabled: true) {
                            onSelect(.accounts)
                        }
                    }

                    // 확인하고 내보내는 순서가 자연스러워 미리보기가 맨 위다.
                    menuGroup(title: "내보내기") {
                        menuRow(icon: "tablecells", label: "보고서 미리보기",
                                tint: DS.Ink.primary, enabled: hasData) {
                            onSelect(.reportPreview)
                        }
                        menuDivider
                        menuRow(icon: "doc.text", label: "월별 회계 보고서 (PDF)",
                                tint: DS.Ink.primary, enabled: hasData) {
                            onSelect(.exportReportPDF)
                        }
                        menuDivider
                        menuRow(icon: "paperclip", label: "영수증 부록 (PDF)",
                                tint: DS.Ink.primary, enabled: hasData) {
                            onSelect(.exportReceiptsPDF)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.medium)
                .padding(.bottom, DS.Spacing.sheetEdge)
            }
        }
        .screenBackground(DS.Surface.page)
    }

    /// 제목 한 줄 + 그 아래 카드 한 장. 프로필 탭의 카드 묶음과 같은 문법이다.
    private func menuGroup<Content: View>(title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text(title).rowSubtext()
            VStack(spacing: 0) { content() }
                .cardStyle(padding: 0)
        }
    }

    /// 아이콘을 지나 글자 앞에서 시작하는 헤어라인. 프로필 탭과 같은 계산이다.
    private var menuDivider: some View {
        Rectangle()
            .fill(DS.Line.default)
            .frame(height: DS.Line.hairline)
            .padding(.leading, DS.Spacing.screen + DS.Icon.feature + DS.Spacing.medium)
    }

    private func menuRow(icon: String, label: String, tint: Color,
                         enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.medium) {
                Image(systemName: icon)
                    .font(DS.Icon.font(DS.Icon.feature))
                    .foregroundColor(tint)
                    .frame(width: DS.Icon.feature)
                Text(label)
                    .typeStyle(DS.Typo.body1)
                    .foregroundColor(tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DS.Icon.font(DS.Icon.m))
                    .foregroundColor(DS.Ink.placeholder)
            }
            .padding(DS.Spacing.screen)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : DS.State.disabledOpacity)
    }
}
