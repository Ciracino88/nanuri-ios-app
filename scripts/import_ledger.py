#!/usr/bin/env python3
"""수기 회계장부 엑셀 → `finance_transactions` INSERT SQL.

    python3 scripts/import_ledger.py --ledger 주거래통장 "회계장부 템플릿.xlsx" > import.sql

**DB 에 직접 쓰지 않는다.** SQL 파일을 뱉을 뿐이고, 실행은 사람이 Supabase 대시보드의
SQL Editor 에 붙여 넣어서 한다. 일회성 이관이라 그게 제일 안전하다 —
service_role 키를 스크립트에 흘릴 이유가 없고, 눈으로 보고 실행할 수 있다.

## 전제 (2026-08-18 확정)

- **주거래통장 = `monthly` 장부 하나.** 연도로도 월로도 자르지 않는다. 자르면
  전월이월이 끊기고, 손으로 채운 그 숫자가 앞 장부 기말잔액과 어긋나도 아무도 모른다.
- **한 파일 안의 월별 시트를 전부 읽는다** (`2025.01` … `2026.08`). 파일을 여러 개
  넘기면 그것들까지 합쳐 **연·월 순으로 이어서** 잔액을 누적한다.
- 연합 행사 통장은 `--type event` 로 따로 만든다.

## 조용히 깨지는 자리 셋

1. **`unique (ledger_id, datetime, amount)`** — 수기 장부에는 시각이 없어서 같은 날
   같은 금액 두 건이 한 건으로 합쳐진다. 그래서 하루 안에서 **줄 순서대로 1분씩
   밀어서** 시각을 만든다 (09:00, 09:01, ...). 순서도 이걸로 보존된다.
2. **`balance` 가 not null** — 시트의 잔액 열은 수식이라 값이 없을 수 있다.
   그래서 우리가 누적해서 채운다. 시트에 값이 있으면 대조까지 한다.
3. **전월이월** — 첫 달 것만 거래로 넣는다. 둘째 달부터는 앞 달 기말잔액과 같은지
   **검산만 하고 버린다.** 그대로 넣으면 그 달 수입이 통째로 부풀어 버린다.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from read_ledger import read_workbook, verify, verify_chain  # noqa: E402

# 수기 장부엔 시각이 없다. 하루의 첫 거래를 여기에 놓고 줄마다 1분씩 민다.
DAY_START_HOUR = 9
KST = "+09"


def sql_str(value: str | None) -> str:
    if value is None or value == "":
        return "null"
    return "'" + value.replace("'", "''") + "'"


def build_rows(paths: list[str]) -> tuple[list[dict], list[str]]:
    """엑셀들을 읽어 INSERT 할 행으로 편다. (행, 확인할 것)

    파일 하나에 월별 시트가 여러 개 있어도(지금 장부가 그렇다) 전부 읽는다.
    파일을 여러 개 넘기면 그것들까지 합쳐 연·월 순으로 이어 붙인다.
    """
    ledgers = sorted((l for p in paths for l in read_workbook(p)),
                     key=lambda l: (l.year, l.month))
    rows: list[dict] = []
    notes: list[str] = list(verify_chain(ledgers))
    balance = 0

    for i, ledger in enumerate(ledgers):
        tag = f"{ledger.year}-{ledger.month:02d}"

        # 같은 날 같은 금액은 아래에서 시각을 밀어 해결하므로 여기선 안 본다.
        for problem in verify(ledger, same_day_duplicates=False):
            notes.append(f"[{tag}] {problem}")

        per_day: dict[object, int] = {}
        for entry in ledger.entries:
            if entry.is_carryover:
                if i == 0:
                    # 첫 달의 전월이월은 **거래가 아니라 시작 잔액이다.**
                    # 앱은 전월이월을 저장된 행에서 읽지 않고 첫 거래의 `balance` 에서
                    # 거꾸로 계산한다 (`FinanceViewModel.openingBalance` =
                    # 첫거래.balance - 첫거래.amount). 그래서 행으로 넣으면
                    # 그 뺄셈이 0이 되어 **전월이월 줄이 0원으로 찍히고**, 그 돈은
                    # 분류 없는 입금이라 **'미분류' 수입으로 따로 뜬다.**
                    # (합계·잔액은 맞는다. 틀리는 건 이름표다.)
                    balance = entry.amount
                else:
                    # 둘째 달부터는 검산만 하고 버린다
                    if entry.amount != balance:
                        notes.append(
                            f"[{tag}] 전월이월 {entry.amount:,} 이 앞 달 기말잔액 "
                            f"{balance:,} 과 다르다 — 사이에 빠진 달이 있는지 본다."
                        )
                continue

            n = per_day.get(entry.day, 0)
            per_day[entry.day] = n + 1
            when = datetime(
                entry.day.year, entry.day.month, entry.day.day, DAY_START_HOUR
            ) + timedelta(minutes=n)

            balance += entry.amount
            if entry.balance_in_sheet is not None and entry.balance_in_sheet != balance:
                notes.append(
                    f"[{tag}] {entry.row}행 잔액 불일치 — 시트 {entry.balance_in_sheet:,} "
                    f"/ 누적 {balance:,}"
                )

            rows.append(
                {
                    "datetime": when.strftime("%Y-%m-%d %H:%M:%S") + KST,
                    "type": "입금" if entry.amount > 0 else "출금",
                    "amount": entry.amount,
                    "balance": balance,
                    "description": entry.description,
                    "category": entry.category,
                    "source": f"{tag} {entry.row}행",
                }
            )

    # 진짜 제약은 (장부, 시각, 금액) 이다. 시각을 다 붙인 뒤에 그걸로 확인한다.
    # 하루에 같은 금액이 60건 넘게 있으면 분이 넘쳐 겹칠 수 있다.
    seen: dict[tuple[str, int], str] = {}
    for r in rows:
        key = (r["datetime"], r["amount"])
        if key in seen:
            notes.append(
                f"{r['source']} 이 {seen[key]} 과 시각·금액이 같다 ({r['datetime']} "
                f"{r['amount']:,}) — 이대로면 한 건으로 합쳐진다."
            )
        seen[key] = r["source"]

    return rows, notes


def emit(rows: list[dict], ledger_name: str, ledger_type: str) -> str:
    """INSERT SQL 을 만든다.

    `values (...)` 에 장부 id 서브쿼리를 줄마다 넣는 대신 **`insert ... select` 로
    한 번만 조인한다.** 줄이 몇백 개가 되어도 장부를 한 번만 찾고, 장부 이름이
    틀렸을 때 한 줄도 안 들어간다 (조인 결과가 비어서 0건이 된다).

    맨 윗줄에만 타입 캐스트를 붙인다. `values` 는 첫 줄로 열 타입을 정하는데,
    전부 null 인 열(분류를 안 적은 달)은 타입을 못 정해서 그냥 두면 에러가 난다.
    """
    name = sql_str(ledger_name)

    def row_sql(r: dict, first: bool) -> str:
        cast = (lambda v, t: f"{v}::{t}") if first else (lambda v, t: v)
        return "    ({}, {}, {}, {}, {}, {})".format(
            cast(sql_str(r["datetime"]), "timestamptz"),
            cast(sql_str(r["type"]), "text"),
            cast(str(r["amount"]), "integer"),
            cast(str(r["balance"]), "integer"),
            cast(sql_str(r["description"]), "text"),
            cast(sql_str(r["category"]), "text"),
        )

    values = ",\n".join(row_sql(r, i == 0) for i, r in enumerate(rows))

    return f"""-- 나누리 수기 장부 이관
-- 만든 날: {datetime.now():%Y-%m-%d %H:%M}
-- 장부: {ledger_name} ({ledger_type}) · 거래 {len(rows)}건
-- 기간: {rows[0]['datetime'][:10]} ~ {rows[-1]['datetime'][:10]}
-- 기말잔액: {rows[-1]['balance']:,}원
--
-- Supabase 대시보드 > SQL Editor 에 붙여 넣어 실행한다.
-- 두 번 실행해도 안전하다 — 같은 (장부, 시각, 금액) 은 건너뛴다.

begin;

-- 장부가 없으면 만들고, 있으면 그대로 쓴다.
insert into public.finance_ledgers (name, type)
select {name}, {sql_str(ledger_type)}
where not exists (
    select 1 from public.finance_ledgers where name = {name}
);

insert into public.finance_transactions
    (ledger_id, datetime, type, amount, balance, description, category)
select l.id, v.datetime, v.type, v.amount, v.balance, v.description, v.category
from (values
{values}
) as v (datetime, type, amount, balance, description, category)
cross join (select id from public.finance_ledgers where name = {name}) as l
on conflict (ledger_id, datetime, amount) do nothing;

commit;
"""


def main() -> None:
    ap = argparse.ArgumentParser(description="수기 장부 엑셀 → INSERT SQL")
    ap.add_argument("files", nargs="+",
                    help="회계장부 엑셀 (한 파일 안의 월별 시트를 전부 읽는다)")
    ap.add_argument("--ledger", required=True, help="장부 이름 (예: 주거래통장)")
    ap.add_argument("--type", default="monthly", choices=["monthly", "event"])
    ap.add_argument("--force", action="store_true", help="검산에 걸려도 SQL 을 뱉는다")
    args = ap.parse_args()

    rows, notes = build_rows(args.files)
    if not rows:
        sys.exit("거래가 하나도 없다.")

    # 사람이 읽을 것은 전부 stderr 로. stdout 은 SQL 만 나가야 파이프가 깨끗하다.
    print(f"거래 {len(rows)}건 · 기말잔액 {rows[-1]['balance']:,}원", file=sys.stderr)
    missing = [r for r in rows if not r["category"]]
    if missing:
        print(f"분류가 빈 거래 {len(missing)}건:", file=sys.stderr)
        for r in missing[:10]:
            print(f"  - {r['source']} {r['description']} {r['amount']:,}", file=sys.stderr)

    if notes:
        print(f"\n확인할 것 {len(notes)}건:", file=sys.stderr)
        for n in notes:
            print(f"  - {n}", file=sys.stderr)
        if not args.force:
            sys.exit("\n검산에 걸려서 멈춘다. 고치고 다시 돌리거나, 알고도 넣으려면 --force.")

    print(emit(rows, args.ledger, args.type))


if __name__ == "__main__":
    main()
