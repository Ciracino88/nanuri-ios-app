#!/usr/bin/env python3
"""수기 회계장부 엑셀을 읽어 거래 목록으로 펴고, 장부가 스스로 맞는지 검산한다.

이 스크립트는 **아무것도 쓰지 않는다.** 읽고, 계산하고, 어긋난 곳을 찍어 줄 뿐이다.
Supabase 에 넣는 건 이걸로 숫자가 맞는 걸 확인한 다음이다.

    python3 scripts/read_ledger.py "회계장부 템플릿.xlsx"

**한 통합문서 안의 월별 시트를 전부 읽는다** (`2025.01` … `2026.08`). 시트 이름에
기대지 않고, A1 이 연·월로 읽히고 '적요' 머리글이 있는 시트를 월별 시트로 본다.
빈 템플릿 시트는 자연히 걸러지고, 같은 달이 두 시트에 있으면 멈춘다.

시트 구조:

    A1              '2025-11' 처럼 연·월
    머리글 줄        월 · 일 · 적요 · 분류 · 수입 · 지출 · 잔액   ← 실제 거래 (왼쪽 블록)
                    분류 · 금액 | 분류 · 금액                    ← 분류별 요약 (오른쪽 블록)

**열 위치는 이름으로 찾는다** (`find_columns`). 열이 하나 끼거나 순서가 바뀌어도
따라간다. 분류 열이 없는 옛 시트도 그대로 읽힌다 — 그때는 분류가 비어 있을 뿐이다.

왼쪽 블록만 거래다. 오른쪽은 파생 데이터라 임포트 대상이 아니지만, **검산에 쓴다** —
거래를 더한 값이 오른쪽과 다르면 둘 중 하나가 틀린 것이다.

월·일은 바뀔 때만 적혀 있고 빈 칸은 위 값을 잇는다 (엑셀에서 눈으로 보던 그대로).
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from datetime import date

try:
    import openpyxl
except ImportError:
    sys.exit("openpyxl 이 필요하다:  python3 -m pip install openpyxl")


CARRYOVER = "전월이월"


@dataclass
class Entry:
    """왼쪽 블록 한 줄 = 거래 한 건."""

    row: int
    day: date
    description: str
    amount: int  # 수입 양수, 지출 음수
    balance_in_sheet: int | None  # 잔액 열이 값으로 저장돼 있을 때만 (수식이면 None)
    category: str | None = None

    @property
    def is_carryover(self) -> bool:
        return self.description.strip() == CARRYOVER


@dataclass
class Ledger:
    year: int
    month: int
    entries: list[Entry] = field(default_factory=list)
    income_summary: dict[str, int] = field(default_factory=dict)
    expense_summary: dict[str, int] = field(default_factory=dict)
    sheet: str = ""   # 어느 시트에서 왔는지 (오류 메시지용)


def parse_year_month(raw) -> tuple[int, int]:
    """A1 을 (연, 월) 로 읽는다.

    엑셀에서 `2025.11` 을 그냥 치면 **숫자**로 저장된다. 그러면 11월과 1월이
    2025.11 / 2025.1 로 갈리는데, 2025.10 은 2025.1 과 같은 수라 10월인지 1월인지
    구분이 안 된다. 그래서 숫자로 들어오면 소수 자릿수를 보고 판단하되,
    애매하면 멈춘다. 시트에는 텍스트('2025-11')로 적는 게 맞다.
    """
    if isinstance(raw, str):
        digits = [int(p) for p in raw.replace(".", "-").replace("/", "-").split("-") if p.strip().isdigit()]
        if len(digits) >= 2:
            return digits[0], digits[1]
        raise ValueError(f"A1 을 연·월로 못 읽었다: {raw!r}")

    if isinstance(raw, (int, float)):
        text = f"{raw}"
        if "." not in text:
            raise ValueError(f"A1 에 월이 없다: {raw!r}")
        year, frac = text.split(".", 1)
        if len(frac) == 1:
            raise ValueError(
                f"A1={raw!r} 은 숫자라 월이 한 자리로 잘렸다 — {frac}월인지 {frac}0월인지 알 수 없다. "
                "시트에 텍스트로 '2025-11' 처럼 적어 달라."
            )
        return int(year), int(frac)

    raise ValueError(f"A1 을 연·월로 못 읽었다: {raw!r}")


def find_columns(ws) -> tuple[int, dict[str, int], list[tuple[str, int, int]]]:
    """머리글 줄을 찾고, 열 위치를 **이름으로** 잡는다.

    열 번호를 코드에 박아 두면 시트에 열이 하나 끼는 순간 조용히 어긋난다.
    '적요' 가 있는 줄을 머리글로 보고, 거기서 이름으로 찾는다.

    돌려주는 것: (머리글 줄 번호, 거래 열 지도, 요약 블록 [(이름, 분류열, 금액열)])

    왼쪽 블록의 '분류'(거래별)와 오른쪽 요약의 '분류'(합계 라벨)는 이름이 같다.
    **수입 열보다 왼쪽에 있는 것만** 거래 분류로 본다.
    """
    header_row = next(
        (r for r in range(1, 11)
         if any(str(ws.cell(r, c).value).strip() == "적요" for c in range(1, ws.max_column + 1))),
        None,
    )
    if header_row is None:
        raise ValueError("'적요' 머리글을 못 찾았다. 시트 구조가 다르다.")

    labels = {c: str(ws.cell(header_row, c).value).strip()
              for c in range(1, ws.max_column + 1) if ws.cell(header_row, c).value}

    def first(name: str, before: int | None = None) -> int | None:
        for c, v in sorted(labels.items()):
            if v == name and (before is None or c < before):
                return c
        return None

    cols = {name: first(name) for name in ("월", "일", "적요", "수입", "지출", "잔액")}
    for name in ("적요", "수입", "지출"):
        if cols[name] is None:
            raise ValueError(f"'{name}' 열이 없다.")
    cols["분류"] = first("분류", before=cols["수입"])

    # 오른쪽 요약: 잔액(없으면 지출) 오른쪽에 있는 분류/금액 짝.
    right_of = cols["잔액"] or cols["지출"]
    summary: list[tuple[str, int, int]] = []
    for c, v in sorted(labels.items()):
        if v == "분류" and c > right_of and labels.get(c + 1) == "금액":
            # 한 줄 위 칸이 블록 이름(수입/지출)이다.
            name = str(ws.cell(header_row - 1, c).value or "").strip()
            if not name:
                name = "수입" if not summary else "지출"
            summary.append((name, c, c + 1))

    return header_row, cols, summary


def read_sheet(ws) -> Ledger:
    """시트 하나 → 장부 하나. 연·월은 A1 에서 읽는다."""
    year, month = parse_year_month(ws["A1"].value)
    ledger = Ledger(year=year, month=month)

    header_row, cols, summary = find_columns(ws)

    def cell(r: int, name: str):
        c = cols.get(name)
        return ws.cell(r, c).value if c else None

    cur_month, cur_day = month, None
    for r in range(header_row + 1, ws.max_row + 1):
        m, d = cell(r, "월"), cell(r, "일")
        desc, income, expense = cell(r, "적요"), cell(r, "수입"), cell(r, "지출")

        # 월·일은 바뀔 때만 적혀 있다. 빈 칸은 위 값을 잇는다.
        if isinstance(m, (int, float)):
            cur_month = int(m)
        if isinstance(d, (int, float)):
            cur_day = int(d)

        if desc is None and income is None and expense is None:
            continue  # 빈 줄
        if cur_day is None:
            sys.exit(f"{r}행: 날짜(일)가 아직 한 번도 안 나왔다.")

        if income and expense:
            sys.exit(f"{r}행: 수입과 지출이 같이 적혀 있다 ({income} / {expense}).")
        if not income and not expense:
            sys.exit(f"{r}행: 금액이 없다 — {desc!r}")

        balance = cell(r, "잔액")
        category = cell(r, "분류")
        amount = int(income) if income else -int(expense)
        ledger.entries.append(
            Entry(
                row=r,
                day=date(year, cur_month, cur_day),
                description=str(desc or "").strip(),
                amount=amount,
                balance_in_sheet=int(balance) if isinstance(balance, (int, float)) else None,
                category=str(category).strip() if category else None,
            )
        )

    # 오른쪽 요약 블록. 합계·잔액 줄은 파생이라 건너뛴다.
    for name, label_col, amount_col in summary:
        into = ledger.income_summary if name == "수입" else ledger.expense_summary
        for r in range(header_row + 1, ws.max_row + 1):
            label, value = ws.cell(r, label_col).value, ws.cell(r, amount_col).value
            if label and isinstance(value, (int, float)) and str(label).strip() not in ("합계", "잔액"):
                into[str(label).strip()] = int(value)

    return ledger


def read_workbook(path: str) -> list[Ledger]:
    """통합문서 안의 **월별 시트를 전부** 읽어 연·월 순으로 돌려준다.

    한 파일에 한 달만 있던 시절엔 `회계장부` 라는 시트 이름을 찾았지만, 지금 장부는
    `2025.01` … `2026.08` 처럼 달마다 시트가 있다. 그래서 이름에 기대지 않고
    **A1 이 연·월로 읽히고 '적요' 머리글이 있는 시트**를 월별 시트로 본다.
    빈 템플릿 시트(A1 이 비어 있다)는 자연히 걸러진다.

    같은 달이 두 시트에 있으면 멈춘다. 예전에 `회계장부` 시트가 특정 달의 오래된
    사본으로 남아 있었는데, 그걸 모르고 읽으면 그 달이 두 번 들어가거나 옛 값이
    이긴다. **조용히 틀리느니 멈추는 게 낫다.**
    """
    wb = openpyxl.load_workbook(path, data_only=True)
    ledgers: list[Ledger] = []
    skipped: list[str] = []
    for ws in wb.worksheets:
        try:
            ledger = read_sheet(ws)
        except ValueError as e:
            skipped.append(f"{ws.title}: {e}")
            continue
        if not ledger.entries:
            skipped.append(f"{ws.title}: 거래가 없다")
            continue
        ledger.sheet = ws.title
        ledgers.append(ledger)

    if not ledgers:
        sys.exit("월별 시트를 하나도 못 읽었다:\n  " + "\n  ".join(skipped))

    seen: dict[tuple[int, int], str] = {}
    for l in ledgers:
        key = (l.year, l.month)
        if key in seen:
            sys.exit(
                f"{l.year}년 {l.month}월이 시트 두 곳에 있다 — '{seen[key]}' 와 '{l.sheet}'. "
                "한쪽이 오래된 사본일 수 있으니 확인하고 지운 뒤 다시 돌린다."
            )
        seen[key] = l.sheet

    return sorted(ledgers, key=lambda l: (l.year, l.month))


def read(path: str) -> Ledger:
    """월별 시트가 정확히 하나일 때만. 여러 달이면 `read_workbook` 을 쓴다."""
    ledgers = read_workbook(path)
    if len(ledgers) != 1:
        sys.exit(f"월별 시트가 {len(ledgers)}개다. read_workbook() 을 쓸 것.")
    return ledgers[0]


def verify_chain(ledgers: list[Ledger]) -> list[str]:
    """달과 달 사이가 이어지는지 본다 — 전월이월이 앞 달 기말잔액과 같은가, 빠진 달은 없는가."""
    problems: list[str] = []
    for prev, cur in zip(ledgers, ledgers[1:]):
        expected_year, expected_month = (prev.year, prev.month + 1) if prev.month < 12 else (prev.year + 1, 1)
        if (cur.year, cur.month) != (expected_year, expected_month):
            problems.append(
                f"{prev.year}-{prev.month:02d} 다음이 {cur.year}-{cur.month:02d} 다 — 사이에 빠진 달이 있다."
            )
        closing = sum(e.amount for e in prev.entries)
        carry = next((e.amount for e in cur.entries if e.is_carryover), None)
        if carry is None:
            problems.append(f"{cur.year}-{cur.month:02d} 에 전월이월이 없다.")
        elif carry != closing:
            problems.append(
                f"{cur.year}-{cur.month:02d} 전월이월 {carry:,} 이 앞 달 기말잔액 {closing:,} 과 다르다 "
                f"(차 {carry - closing:+,})."
            )
    return problems


def verify(ledger: Ledger, *, same_day_duplicates: bool = True) -> list[str]:
    """장부가 스스로 맞는지 본다. 틀린 곳을 문장으로 돌려준다.

    `same_day_duplicates=False` 는 임포트 스크립트용이다. 저쪽은 하루 안에서
    시각을 1분씩 밀어 유니크 제약을 이미 피하므로, 같은 날 같은 금액이 있어도
    문제가 아니다. 사람이 눈으로 볼 때만 경고한다.
    """
    problems: list[str] = []

    # 1. 누적 잔액이 시트의 F열과 같은가
    running = 0
    for e in ledger.entries:
        running += e.amount
        if e.balance_in_sheet is not None and e.balance_in_sheet != running:
            problems.append(
                f"{e.row}행 잔액이 안 맞는다 — 시트 {e.balance_in_sheet:,} / 누적 {running:,} "
                f"({e.description})"
            )

    # 2. 수입·지출 합이 오른쪽 요약과 같은가
    income = sum(e.amount for e in ledger.entries if e.amount > 0)
    expense = -sum(e.amount for e in ledger.entries if e.amount < 0)
    if ledger.income_summary:
        want = sum(ledger.income_summary.values())
        if want != income:
            problems.append(f"수입 합계가 안 맞는다 — 요약 {want:,} / 거래 {income:,}")
    if ledger.expense_summary:
        want = sum(ledger.expense_summary.values())
        if want != expense:
            problems.append(f"지출 합계가 안 맞는다 — 요약 {want:,} / 거래 {expense:,}")

    # 3. 같은 날 같은 금액이 두 번 있는가
    #    finance_transactions 에 unique (ledger_id, datetime, amount) 가 걸려 있어서,
    #    시각 없이 날짜만으로 넣으면 이런 짝이 한 건으로 합쳐진다.
    if same_day_duplicates:
        seen: dict[tuple[date, int], int] = {}
        for e in ledger.entries:
            key = (e.day, e.amount)
            if key in seen:
                problems.append(
                    f"{e.row}행은 {seen[key]}행과 날짜·금액이 같다 ({e.day} {e.amount:,}) "
                    "— 시각을 1분씩 밀어 넣어야 한 건으로 합쳐지지 않는다."
                )
            seen[key] = e.row

    return problems


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    ledgers = read_workbook(sys.argv[1])
    all_entries = [e for l in ledgers for e in l.entries]
    first, last = ledgers[0], ledgers[-1]

    print(f"월별 시트 {len(ledgers)}개 · 거래 {len(all_entries)}건")
    print(f"기간: {first.year}-{first.month:02d} ~ {last.year}-{last.month:02d}\n")

    # 같은 날 같은 금액은 `import_ledger.py` 가 시각을 1분씩 밀어 알아서 푼다.
    # 그래서 여기서는 **실패가 아니라 참고**로 따로 센다. 섞으면 진짜 문제가 묻힌다.
    problems: list[str] = []
    dup_count = 0
    print(f"{'달':>9} {'거래':>4} {'수입':>12} {'지출':>12} {'기말잔액':>12}  검산")
    for l in ledgers:
        income = sum(e.amount for e in l.entries if e.amount > 0 and not e.is_carryover)
        expense = -sum(e.amount for e in l.entries if e.amount < 0)
        closing = sum(e.amount for e in l.entries)
        mine = verify(l, same_day_duplicates=False)
        dup_count += len(verify(l)) - len(mine)
        problems += [f"[{l.year}-{l.month:02d}] {p}" for p in mine]
        mark = "통과" if not mine else f"확인 {len(mine)}건"
        n = len([e for e in l.entries if not e.is_carryover])
        print(f"{l.year}-{l.month:02d} {n:>4} {income:>12,} {expense:>12,} {closing:>12,}  {mark}")

    carryover = next((e for e in first.entries if e.is_carryover), None)
    if carryover:
        print(f"\n시작 잔액 {carryover.amount:,}원 ({carryover.day}) "
              f"→ 기말 {sum(e.amount for e in last.entries):,}원")

    chain = verify_chain(ledgers)
    problems += chain
    print(f"달 사이 연결: {'끊긴 곳 없음' if not chain else f'{len(chain)}건 확인 필요'}")

    missing = [e for l in ledgers for e in l.entries if not e.category and not e.is_carryover]
    if missing:
        print(f"\n분류가 없는 거래 {len(missing)}건 / {len(all_entries)}건")
        for e in missing[:10]:
            print(f"  - {e.day} {e.description} {e.amount:,}")
    else:
        print("모든 거래에 분류가 있다.")

    if dup_count:
        print(f"\n같은 날·같은 금액인 거래 {dup_count}쌍 — 문제는 아니다. "
              "임포트할 때 하루 안에서 시각을 1분씩 밀어 구분한다.")

    if problems:
        print(f"\n확인할 것 {len(problems)}건:")
        for p in problems:
            print(f"  - {p}")
        sys.exit(1)
    print("\n검산 통과 — 잔액·합계·달 사이 연결이 전부 맞는다.")


if __name__ == "__main__":
    main()
