#!/usr/bin/env python3
"""수기 회계장부의 적요로 분류를 추정하고, 시트의 요약 블록으로 검산한다.

    python3 scripts/classify_ledger.py "회계장부 템플릿 (3) - 수정.xlsx"
    python3 scripts/classify_ledger.py --csv 분류.csv <파일>

**아무것도 쓰지 않는다.** 추정하고, 맞는지 확인하고, 어긋난 곳을 찍어 줄 뿐이다.

## 왜 검산이 되나

수기 장부의 왼쪽 블록에는 분류 열이 없다. 분류는 오른쪽 블록에 **월별 합계로만**
있어서 어느 거래가 어느 분류인지 파일 어디에도 없다.

그런데 그 월별 합계가 정답지 역할을 한다 — 적요로 추정한 분류를 월별로 합산해서
오른쪽 블록과 **한 원까지 맞으면 매핑이 옳다는 게 증명된다.** 틀린 거래가 있다면
어느 분류의 합이든 반드시 어긋나기 때문이다. (두 거래가 서로 반대 방향으로 같은
금액만큼 잘못 분류되면 상쇄될 수 있지만, 그건 아래 리포트에서 분류별 차액이
쌍으로 나타나므로 눈에 띈다.)

## 시트 구조

`2025.01` 처럼 연·월 이름을 가진 시트만 읽는다.

    A~F  월 · 일 · 적요 · 수입 · 지출 · 잔액      ← 거래 (왼쪽 블록)
    G~J  분류 · 금액 | 분류 · 금액                ← 월별 요약 (오른쪽 블록, 정답지)

`합계` · `잔액` · `전월이월` 은 요약 블록의 머리·꼬리라 분류에서 뺀다.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict

try:
    import openpyxl
except ImportError:
    sys.exit("openpyxl 이 필요하다:  python3 -m pip install openpyxl")


CARRYOVER = "전월이월"
NOT_A_CATEGORY = {"합계", "잔액", "분류", CARRYOVER}

# ── 분류 규칙 ──────────────────────────────────────────────────────────────
#
# 위에서부터 먼저 걸리는 것이 이긴다. **순서가 곧 규칙이다** — 좁은 것을 위에,
# 넓은 것을 아래에 둔다. 예: '선교 헌금 봉투'(비품)와 '사랑의 쌀 헌금'(기부금)은
# '선교 헌금'(선교비)보다 위에 있어야 한다.
#
# 근거는 시트의 `그라운드 룰` 과 사용자 확인 사항이다:
#   - 선교비  = 해외 봉사자에게 넘기는 기부금
#   - 기부금  = 국내 대상 (사랑의 쌀, 연탄)
#   - 행사비  = 행사 준비 모임·식대·참가비·선물 등 (연례 이벤트 포함)
#   - 비품 구매 = 청년부 비품함에 넣어두고 쓰는 것 (간식·봉투·카드팩·기기)
#   - 경조사비 = 결혼·장례·군 입대

INCOME_RULES: list[tuple[str, str]] = [
    (r"이자", "이자"),
    (r"반환금", "기타 (반환금)"),
    (r"선교\s*헌금", "선교비"),
    (r"후원금|찬조금", "후원금"),
    (r"회비|참가비", "회비"),
    (r"교회\s*여름\s*행사", "회비"),
    (r"헌금", "헌금"),
]

EXPENSE_RULES: list[tuple[str, str]] = [
    (r"수수료", "수수료"),
    (r"심방비", "심방비"),
    # ── 선교비보다 위: '헌금'·'선교'가 들어가지만 다른 분류인 것들 ──
    (r"헌금\s*봉투|물품\s*구매비", "비품 구매"),
    (r"사랑의\s*쌀|연탄\s*후원금\s*송금", "기부금"),
    (r"선교\s*모임", "행사비"),
    (r"수련회\s*헌금", "행사비"),
    # ── 선교비 ──
    (r"단기선교\s*지원금", "선교비"),
    (r"선교\s*헌금|선교비", "선교비"),
    # ── 경조사비 ──
    (r"축의금|부의금|조의금|군\s*입대", "경조사비"),
    # ── 지원비: 찬양팀 지원 (엠티 지원비 포함) ──
    (r"찬양팀.*지원", "지원비"),
    # ── 비품 구매 ──
    (r"간식비|카드팩|컴퓨터\s*수리", "비품 구매"),
    # ── 도서비: 문자 그대로인 것만. '새신자 교재'는 행사비였다 ──
    (r"^도서비", "도서비"),
]

EXPENSE_DEFAULT = "행사비"


def classify(description: str, is_income: bool) -> str:
    """적요 한 줄 → 분류. 지출에서 아무 규칙에도 안 걸리면 행사비다."""
    text = description.strip()
    rules = INCOME_RULES if is_income else EXPENSE_RULES
    for pattern, category in rules:
        if re.search(pattern, text):
            return category
    return "" if is_income else EXPENSE_DEFAULT


# ── 시트 읽기 ──────────────────────────────────────────────────────────────

SHEET_NAME = re.compile(r"^(\d{4})[.\-](\d{2})$")


def find_columns(ws) -> dict[str, int]:
    """3행 머리글로 열 위치를 찾는다.

    `분류` 열을 끼우기 전(적요·수입·지출·잔액)과 끼운 뒤(적요·분류·수입·지출·잔액)를
    **둘 다** 읽을 수 있어야 한다. 그래서 위치를 고정하지 않고 이름으로 찾는다.
    오른쪽 요약 블록에도 `분류` 가 있으므로 왼쪽 블록만 본다 — 잔액 열까지가 왼쪽이다.
    """
    header = {}
    for col in range(1, ws.max_column + 1):
        name = ws.cell(3, col).value
        if isinstance(name, str):
            header.setdefault(name.strip(), col)
        if name == "잔액":
            break  # 여기까지가 왼쪽 블록
    missing = [k for k in ("적요", "수입", "지출") if k not in header]
    if missing:
        raise ValueError(f"머리글을 못 찾았다: {missing}")
    return header


def read_month(ws, year: int, month: int) -> dict:
    """시트 하나 → {거래 목록, 요약 블록 정답지}."""
    col = find_columns(ws)
    c_desc, c_in, c_out = col["적요"], col["수입"], col["지출"]
    c_day = col.get("일", 2)
    summary_start = col.get("잔액", 6) + 1  # 오른쪽 요약 블록의 첫 열

    entries = []
    for row in range(4, ws.max_row + 1):
        desc = ws.cell(row, c_desc).value
        if not desc:
            continue
        desc = str(desc).strip()
        if desc == CARRYOVER:
            continue  # 거래가 아니라 앞 달에서 이어온 잔액이다
        day = ws.cell(row, c_day).value
        income = ws.cell(row, c_in).value
        expense = ws.cell(row, c_out).value
        for value, is_income in ((income, True), (expense, False)):
            if isinstance(value, (int, float)) and value:
                entries.append({
                    "row": row,
                    "day": int(day) if isinstance(day, (int, float)) else None,
                    "desc": desc,
                    "amount": int(value),
                    "is_income": is_income,
                    "category": classify(desc, is_income),
                })

    stated = {"income": defaultdict(int), "expense": defaultdict(int)}
    s = summary_start
    for row in range(4, ws.max_row + 1):
        for label_col, amount_col, side in ((s, s + 1, "income"), (s + 2, s + 3, "expense")):
            label = ws.cell(row, label_col).value
            amount = ws.cell(row, amount_col).value
            if isinstance(label, str) and label.strip() not in NOT_A_CATEGORY:
                if isinstance(amount, (int, float)):
                    stated[side][label.strip()] += int(amount)
    return {"year": year, "month": month, "entries": entries,
            "stated": {k: dict(v) for k, v in stated.items()}}


def read_all(path: str) -> list[dict]:
    wb = openpyxl.load_workbook(path, data_only=True)
    months = []
    for name in wb.sheetnames:
        m = SHEET_NAME.match(name.strip())
        if m:
            months.append(read_month(wb[name], int(m.group(1)), int(m.group(2))))
    if not months:
        sys.exit(f"연·월 이름의 시트가 없다. 있는 시트: {wb.sheetnames}")
    return sorted(months, key=lambda x: (x["year"], x["month"]))


# ── 검산 ──────────────────────────────────────────────────────────────────

def reconcile(month: dict) -> dict:
    """추정 합계 vs 시트 요약. 분류별 차액을 돌려준다 (빈 dict = 완전 일치)."""
    guessed = {"income": defaultdict(int), "expense": defaultdict(int)}
    for e in month["entries"]:
        side = "income" if e["is_income"] else "expense"
        guessed[side][e["category"]] += e["amount"]

    diffs = {}
    for side in ("income", "expense"):
        stated = dict(month["stated"][side])
        # 전월이월은 거래가 아니라 요약에만 있으므로 비교에서 뺀다
        stated.pop(CARRYOVER, None)
        for category in set(stated) | set(guessed[side]):
            got = guessed[side].get(category, 0)
            want = stated.get(category, 0)
            if got != want:
                diffs[(side, category)] = (got, want)
    return diffs


def main() -> None:
    ap = argparse.ArgumentParser(description="적요로 분류를 추정하고 요약 블록으로 검산한다")
    ap.add_argument("path", help="회계장부 엑셀 파일")
    ap.add_argument("--csv", help="추정 결과를 CSV 로 저장할 경로")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="어긋난 달의 거래를 분류별로 펼쳐 본다")
    args = ap.parse_args()

    months = read_all(args.path)
    total_entries = sum(len(m["entries"]) for m in months)
    clean, dirty = [], []

    for m in months:
        diffs = reconcile(m)
        label = f"{m['year']}.{m['month']:02d}"
        (clean if not diffs else dirty).append((label, m, diffs))

    print(f"시트 {len(months)}개 · 거래 {total_entries}건\n")
    print(f"검산 통과: {len(clean)}개월 / {len(months)}개월")
    if clean:
        print("  " + " ".join(label for label, _, _ in clean))

    if dirty:
        print(f"\n어긋난 달: {len(dirty)}개월")
        for label, m, diffs in dirty:
            print(f"\n  [{label}]")
            for (side, category), (got, want) in sorted(diffs.items()):
                side_ko = "수입" if side == "income" else "지출"
                mark = "추정에만 있음" if want == 0 else ("시트에만 있음" if got == 0 else "")
                print(f"    {side_ko} · {category or '(미분류)'}: "
                      f"추정 {got:,} vs 시트 {want:,} (차 {got - want:+,}) {mark}")
                if args.verbose:
                    for e in m["entries"]:
                        same_side = (side == "income") == e["is_income"]
                        if same_side and e["category"] == category:
                            print(f"        {e['row']:>3}행 {e['amount']:>10,}  {e['desc']}")

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow(["연", "월", "일", "행", "적요", "수입/지출", "금액", "추정분류"])
            for m in months:
                for e in m["entries"]:
                    w.writerow([m["year"], m["month"], e["day"], e["row"], e["desc"],
                                "수입" if e["is_income"] else "지출",
                                e["amount"], e["category"]])
        print(f"\nCSV 저장: {args.csv}")

    sys.exit(0 if not dirty else 1)


if __name__ == "__main__":
    main()
