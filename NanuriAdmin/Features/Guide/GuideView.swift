import SwiftUI

/// 나누리 회계 시스템이 어떻게 운영되는지 소개하는 안내 페이지.
struct GuideView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    introCard
                    improvementSection
                    transparencySection
                    accountsSection
                    budgetFlowSection
                    eventFlowSection
                    importSection
                    footerNote
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("이용 안내")
        }
    }

    // MARK: - 인트로

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("나누리 회계는 이렇게 운영돼요")
                .font(.title3)
                .fontWeight(.bold)
            Text("통장 3개로 예산을 나눠 관리하고, 매달 예산을 받아 쓰고 남은 잔액을 돌려주는 구조예요.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - 전환 이점 (농협 → 토스 모임통장 + 앱)

    private var improvementSection: some View {
        GuideCard(title: "이렇게 좋아져요", icon: "sparkles", color: .pink) {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    improvementRow(
                        icon: "wonsign.circle", color: .green, topic: "수수료",
                        before: "현금 입출금 수수료", after: "어느 ATM이든 월 30회 무료")
                    Text("현금 거래는 주로 헌금 입금이라 월 30회를 넘길 일이 거의 없어요. 사실상 무료예요.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 48)
                }
                Divider()
                improvementRow(
                    icon: "bolt.fill", color: .orange, topic: "입출금",
                    before: "ONLY NH ATM", after: "즉시 송금")
                Divider()
                improvementRow(
                    icon: "creditcard", color: .blue, topic: "통장 재발급",
                    before: "약 6개월마다", after: "월 2건만 → 거의 없음")
                Divider()
                improvementRow(
                    icon: "doc.text", color: .indigo, topic: "장부",
                    before: "손으로 작성·제출", after: "내역서 넣으면 자동 생성")
                Divider()
                improvementRow(
                    icon: "photo", color: .teal, topic: "영수증",
                    before: "종이로 보관", after: "사진 첨부 · 클라우드 보관")
            }
        }
    }

    private func improvementRow(icon: String, color: Color, topic: String, before: String, after: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(topic)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                HStack(spacing: 6) {
                    Text(before)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(after)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 투명성

    private var transparencySection: some View {
        GuideCard(title: "함께, 투명하게 관리해요", icon: "person.3", color: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                bulletRow("모임통장에 임원진을 멤버로 초대하면, 모두가 모든 입출금을 실시간으로 직접 봐요.")
                bulletRow("앱이 거래 분류·영수증·결산 보고서·클라우드 보관까지 더해요.")
                bulletRow("담당이 바뀌어도 자료가 그대로 남아 인수인계가 쉬워요.")
            }
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundColor(.purple)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 통장 구조

    private var accountsSection: some View {
        GuideCard(title: "통장 3개", icon: "creditcard", color: .blue) {
            VStack(spacing: 12) {
                accountRow(
                    color: .green,
                    icon: "building.columns",
                    name: "교회 통장 (농협)",
                    role: "예산의 출처. 월초에 예산을 보내주고, 월말에 남은 잔액을 돌려받아요."
                )
                Divider()
                accountRow(
                    color: .blue,
                    icon: "wonsign.circle",
                    name: "주거래통장 (회계 명의)",
                    role: "헌금·후원·지출 등 모든 거래가 여기에 찍혀요. 월별 회계 장부의 기준이 되는 통장이에요."
                )
                Divider()
                accountRow(
                    color: .orange,
                    icon: "flag.checkered",
                    name: "연합 행사용 통장 (회계 명의)",
                    role: "연합 행사 전용. 행사비와 행사 후원금이 오가는 통장이에요."
                )
            }
        }
    }

    private func accountRow(color: Color, icon: String, name: String, role: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(role)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 예산 흐름

    private var budgetFlowSection: some View {
        GuideCard(title: "매달 예산 흐름", icon: "arrow.triangle.2.circlepath", color: .indigo) {
            VStack(alignment: .leading, spacing: 0) {
                stepRow(index: 1, isLast: false,
                        title: "월초 — 예산 받기",
                        detail: "교회 통장에서 재정의 1할을 주거래통장으로 받아와요. 부족하면 추가로 입금받아요.")
                stepRow(index: 2, isLast: false,
                        title: "한 달 — 운영",
                        detail: "주거래통장에서 헌금·후원을 받고 지출해요. 모든 거래가 이 통장에 기록돼요.")
                stepRow(index: 3, isLast: true,
                        title: "월말 — 잔액 반환",
                        detail: "남은 잔액을 교회 통장으로 돌려보내요.")

                Text("농협 통장엔 이 예산·잔액 2건만 찍혀요. 그래서 통장이 훨씬 천천히 차고, 6개월마다 하던 재발급이 몇 년에 한 번으로 줄어들어요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: - 연합 행사

    private var eventFlowSection: some View {
        GuideCard(title: "연합 행사", icon: "flag.checkered", color: .orange) {
            VStack(alignment: .leading, spacing: 0) {
                stepRow(index: 1, isLast: false,
                        title: "행사비 이체",
                        detail: "주거래통장에서 연합 행사용 통장으로 행사비를 먼저 보내요.")
                stepRow(index: 2, isLast: false,
                        title: "후원금 수령",
                        detail: "그 행사에 대한 후원금은 행사용 통장으로 받아요.")
                stepRow(index: 3, isLast: true,
                        title: "행사 결산",
                        detail: "행사용 통장 거래내역으로 행사 결산 장부를 만들어요.")
            }
        }
    }

    // MARK: - 거래내역서 가져오기

    private var importSection: some View {
        GuideCard(title: "거래내역서 가져오기", icon: "square.and.arrow.down", color: .teal) {
            VStack(alignment: .leading, spacing: 10) {
                Text("토스뱅크 앱에서 거래내역서를 PDF로 내보내 이 앱으로 공유하면 돼요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    pathStep("전체(메뉴) → 토스뱅크 → 나누리 모임통장")
                    pathStep("관리 → 문서 관리 → 거래내역서")
                    pathStep("PDF 선택 → 발급방법(PDF로 저장하기) → 한글")
                    pathStep("발급 계좌 선택(나누리 모임통장) → 거래내역 지정")
                    pathStep("PDF 화면에서 공유하기 → 더 보기 → 나누리 회계 앱 선택")
                }
            }
        }
    }

    private func pathStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chevron.right.circle.fill")
                .font(.caption)
                .foregroundColor(.teal)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 공용 스텝 행

    private func stepRow(index: Int, isLast: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 16)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footerNote: some View {
        Text("각 통장은 재정 탭에서 '장부'로 따로 관리해요.\n주거래통장은 월별 회계, 행사용 통장은 행사 결산으로 만들면 돼요.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

/// 아이콘·제목이 있는 안내 카드 컨테이너.
private struct GuideCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}
