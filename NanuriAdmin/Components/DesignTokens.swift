import SwiftUI
import UIKit

// MARK: - 색 유틸

extension Color {
    /// 16진수 리터럴 하나로 색을 만든다. 토큰 표를 옮겨 적기 위한 것이고,
    /// **화면 코드에서 직접 부르지 않는다** — 색은 전부 `DS.Ink`/`DS.Surface`/`DS.Line`/
    /// `DS.Palette` 를 거친다.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// 밝은 화면과 어두운 화면에서 다른 값을 갖는 색.
    ///
    /// 원문은 **밝은 모드 값만 발행한다.** 다크 모드 alias 표가 공개돼 있지 않다는
    /// 점을 원문이 Known Gaps 첫 줄에 직접 적어 뒀다. 그래서 어두운 쪽 값은
    /// **이 앱이 정한 것**이다 — 무채색 사다리를 뒤집고, 파랑은 어두운 바탕에서
    /// 눈이 부시지 않게 한 단 올린 명도를 쓴다.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

// MARK: - 원시 팔레트

/// 참조 디자인 시스템의 base 팔레트를 옮긴 원시 값.
///
/// **이 표는 화면이 직접 참조하지 않는다.** 원문 규칙이 그렇다 — product 색은
/// 시맨틱·컴포넌트 alias 로만 호출하고, base 팔레트는 새 role 을 만들 때만
/// 직접 본다. 화면은 `DS.Ink`/`DS.Surface`/`DS.Line`/`DS.Palette` 만 쓴다.
///
/// ## 값의 출처와 정확도
///
/// 원문은 색을 **OKLCH 로 발행**하는데 SwiftUI 는 `oklch()` 를 못 먹는다.
/// 그래서 sRGB 로 변환해 적었고, **변환값은 근사다.**
///
/// 예외가 하나 있다 — `blue500` 은 변환값(`#2887EE`)이 아니라 **공식 hex
/// `#3182F6`** 이다. 원문이 Colors 절 서두에서 "값을 맞춰 볼 배포물을 찾지 못했고
/// 이 절의 색 토큰은 산문 서술 위에 서 있다"고 밝히는데, 그중 `#3182F6` 만은
/// 미니앱 브랜딩 가이드에 `brand.primaryColor` 로 노출된 공식값이다.
/// 실제로 둘은 어긋난다 — 발행된 OKLCH 를 변환하면 채도가 0.015 낮고 색상각이
/// 4.2° 틀어진, 눈에 띄게 탁한 파랑이 나온다. **브랜드의 실제 값을 우선한다.**
///
/// 나머지 토큰은 대조할 공식 hex 가 없어 변환값을 그대로 쓴다.
enum Ramp {

    // 브랜드 — 화면당 단 하나의 주요 동작에만 예약된다.
    /// 공식 hex. 아래 주석의 OKLCH 는 원문 발행값이며 이 hex 와 정확히 일치하지 않는다.
    static let blue500: UInt32 = 0x3182F6  // 공식값 · 원문 oklch(0.624 0.176 254) → #2887EE
    static let blue600: UInt32 = 0x1065CC  // ≈ oklch(0.522 0.176 257) — pressed 단계
    static let blue700: UInt32 = 0x0D56BC  // ≈ oklch(0.476 0.174 259)
    static let blue50: UInt32 = 0xEAF5FF   // ≈ oklch(0.965 0.020 250) — brand-weak 바탕

    // 무채 — 차갑게 기운 중성색이다. **grey900 은 순수 검정이 아니다.**
    static let grey900: UInt32 = 0x141F2C  // ≈ oklch(0.234 0.030 254) — 본문 글자
    static let grey800: UInt32 = 0x2D3A48  // ≈ oklch(0.342 0.030 253)
    static let grey700: UInt32 = 0x4B5765  // ≈ oklch(0.452 0.028 253) — 보조 글자
    static let grey600: UInt32 = 0x6A7480  // ≈ oklch(0.555 0.022 253)
    static let grey500: UInt32 = 0x87919C  // ≈ oklch(0.652 0.020 252)
    static let grey400: UInt32 = 0xA7B0B9  // ≈ oklch(0.752 0.016 251) — 흐린 글자 · 강한 선
    static let grey300: UInt32 = 0xC5CBD2  // ≈ oklch(0.840 0.012 248)
    static let grey200: UInt32 = 0xDEE3E7  // ≈ oklch(0.913 0.008 247) — 기본 구분선
    static let grey150: UInt32 = 0xE0E4E8  // ≈ oklch(0.918 0.007 247)
    static let grey100: UInt32 = 0xEEF1F4  // ≈ oklch(0.957 0.005 247) — 보조 표면
    static let grey50: UInt32 = 0xF6F8FA   // ≈ oklch(0.978 0.003 247)
    static let white: UInt32 = 0xFFFFFF

    // 시맨틱
    static let red500: UInt32 = 0xF03848   // ≈ oklch(0.628 0.218 22) — 오류 · 되돌릴 수 없는 것
    static let red600: UInt32 = 0xEE3848   // ≈ oklch(0.626 0.216 22)
    static let green500: UInt32 = 0x007738 // ≈ oklch(0.493 0.143 154) — 성공
    static let orange500: UInt32 = 0xFF8800 // ≈ oklch(0.748 0.183 56) — 주의
    static let navy900: UInt32 = 0x010A25  // ≈ oklch(0.155 0.060 261) — 그림자·알파의 베이스

    /// 일러스트 자산의 얼굴색. **표면 색이 아니다** — UI 에 칠하지 않는다.
    /// 원문이 이 노랑을 일러스트/이모지 전용으로 못 박는다. 이름만 남겨 둔다.
    static let yellow500: UInt32 = 0xFCC63E // ≈ oklch(0.853 0.156 86)
}
