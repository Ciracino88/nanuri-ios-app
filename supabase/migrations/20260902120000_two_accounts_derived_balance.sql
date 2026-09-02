-- 통장 둘, 장부 하나 — 그리고 잔액을 저장에서 유도로
--
-- 지금까지의 전제는 "장부 = 통장 하나" 였고, 그래서 거래마다 그 통장의 잔액을
-- 통째로 들고 있었다. 토스 거래내역서를 베끼던 시절엔 은행이 계산해 준 숫자라
-- 뜻이 있었다.
--
-- 실제 운영은 통장이 둘이다 — 헌금을 받는 교회법인 농협통장, 청구를 실시간으로
-- 처리하는 토스 모임통장. 그리고 **그 둘을 하나의 장부에 적는다.**
--
-- 두 통장이 한 장부에 섞이는 순간 `balance` 는 **어느 통장의 잔액도 아니게 된다.**
-- 농협 거래 다음 줄에 모임 거래가 오면 그 줄의 잔액은 아무것도 아니다.
-- 그래서 이 마이그레이션은 두 가지를 한다.
--
--   ① 거래마다 **어느 통장인지**를 적는다 (`account_id`)
--   ② 잔액을 저장하지 않고 **통장별 개시잔액 + 누적**으로 유도한다
--
-- 잃는 것은 없다. 지금 들어 있는 273건의 `balance` 는 은행이 말해 준 값이 아니라
-- **임포트 스크립트가 엑셀 잔액을 누적해 채운 값**이다 (원본 시트의 잔액 열은
-- 수식이라 값이 없었다). 유도로 바꿔도 같은 숫자가 나온다.
--
-- 검증의 근거는 딴 데 있다 — 모임통장은 월말 결산 때 잔액을 농협으로 돌려보내
-- **매달 0으로 떨어진다.** `예산 수령 + 후원금 = 지출 + 잔액 반환` 이 한 줄만
-- 빠져도 안 맞는다. 저장된 잔액이 필요 없는 검산이다.

-- ---------------------------------------------------------------------------
-- 1. 통장
-- ---------------------------------------------------------------------------
-- 개시잔액이 살 곳이 필요해서 표로 만든다. `account` 를 자유 문자열로 두면
-- 그 값을 어디에도 못 붙인다. 헌금 수령처가 모임통장으로 승인나서 통장이 하나로
-- 줄 때도 이 표만 고치면 된다.
--
-- 이름에 check 제약을 걸지 않는다. 통장은 늘어나거나 줄 수 있고, 좁히는 제약은
-- 얻는 것 없이 나중에 걸림돌만 된다.
create table public.finance_accounts (
    id              uuid        primary key default gen_random_uuid(),
    ledger_id       uuid        not null references public.finance_ledgers(id) on delete cascade,

    name            text        not null,
    -- 장부가 이 통장을 적기 시작하는 시점에 이미 들어 있던 돈.
    -- 통장 잔액 = opening_balance + 그 통장 거래들의 누적.
    opening_balance integer     not null default 0,
    sort_order      integer     not null default 0,
    created_at      timestamptz not null default now(),

    unique (ledger_id, name)
);

create index finance_accounts_ledger_idx
    on public.finance_accounts (ledger_id, sort_order);

alter table public.finance_accounts enable row level security;

create policy "관리자 전용 통장" on public.finance_accounts
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- 2. 장부 이름 — 통장 이름을 갖고 있었다
-- ---------------------------------------------------------------------------
-- 이관할 때 `주거래통장` 으로 들어갔는데, 장부는 하나고 통장이 둘이라 장부가
-- 통장 이름을 가지면 안 된다. 게다가 그 273건은 모임통장이 없던 시절 **농협
-- 기준**으로 쓴 것이라 하필 반대쪽 통장 이름이 붙어 있었다.
update public.finance_ledgers
   set name = '나누리 회계'
 where name = '주거래통장';

-- ---------------------------------------------------------------------------
-- 3. 통장 두 개를 넣는다
-- ---------------------------------------------------------------------------
-- **농협 개시잔액은 손으로 적지 않고 데이터에서 뽑는다.**
-- 이관할 때 `전월이월` 을 거래로 넣지 않고 "누적의 출발점" 으로만 썼기 때문에,
-- 첫 거래의 `balance - amount` 가 곧 그 값이다 (= 엑셀 2025.01 전월이월).
-- 손으로 적으면 1원만 어긋나도 뒤의 273건 잔액이 전부 밀린다.
--
-- 모임은 0 이다. 거래내역서로 확인했다 — 첫 거래(2026-08-01 이자 15원) 이전
-- 잔액이 0 이었고, 0 에서 출발한 잔액 체인이 8월 22건 전부와 한 원까지 맞는다.
insert into public.finance_accounts (ledger_id, name, opening_balance, sort_order)
select l.id,
       '농협',
       coalesce((select t.balance - t.amount
                   from public.finance_transactions t
                  where t.ledger_id = l.id
                  order by t.datetime, t.created_at
                  limit 1), 0),
       1
  from public.finance_ledgers l
union all
select l.id, '모임', 0, 2
  from public.finance_ledgers l;

-- ---------------------------------------------------------------------------
-- 4. 거래에 통장을 붙인다
-- ---------------------------------------------------------------------------
-- `counter_account_id` 가 이 마이그레이션의 핵심이다.
--
-- 농협에서 모임으로 400만원을 옮기는 것은 **한 사건**인데 통장 둘에 걸친다.
-- 두 줄(농협 출금 + 모임 입금)로 적으면 그 둘이 같은 사건이라는 걸 따로 짝지어야
-- 하고, 짝이 깨지면 조용히 틀어진다. 한 줄이 양쪽을 알면 그런 일이 없다.
--
--   비어 있으면  → 실제 수입·지출
--   차 있으면    → 내부 이체 (amount 는 `account_id` 기준, 상대편은 부호가 반대)
--
-- 이 한 칸이 세 가지를 한꺼번에 한다.
--   ① 통장별 잔액 유도 — 상대 통장 쪽은 부호를 뒤집어 더한다
--   ② 보고서에서 내부 이체 자동 제외 — 안 그러면 그 달 지출이 부풀어 보인다.
--      2026-08 이 실제로 그랬다: 장부상 지출 4,974,200 중 4,000,000 이 내부 이체라
--      진짜 지출(974,200)의 5.1배로 보였다.
--   ③ `예산 수령`·`잔액 반환` 은 이 형태에서 **파생되는 이름**이라 사람이 안 고른다
--
-- on delete restrict — 거래가 달린 통장은 못 지운다. 지워지면 그 거래들이 어느
-- 통장 것인지 영영 알 수 없다.
alter table public.finance_transactions
    add column account_id         uuid references public.finance_accounts(id) on delete restrict,
    add column counter_account_id uuid references public.finance_accounts(id) on delete restrict;

-- 백필 — 기존 273건은 전부 농협이다.
--
-- 근거 둘이 서로 독립적이다.
--   ① 내부 이체 분류가 하나도 없다. 두 통장이 돌고 있었다면 `예산 수령`·`잔액 반환`
--      이 20개월간 각 20건 안팎 있어야 한다.
--   ② `헌금` 이 80건 있다. 헌금은 모임통장으로 못 받는다(승인 안 남). 헌금이 장부에
--      있다는 것 자체가 **농협 내역을 보고 쓴 장부**라는 뜻이다.
update public.finance_transactions t
   set account_id = a.id
  from public.finance_accounts a
 where a.ledger_id = t.ledger_id
   and a.name      = '농협'
   and t.account_id is null;

alter table public.finance_transactions
    alter column account_id set not null;

-- 자기 자신과의 이체는 이체가 아니다.
alter table public.finance_transactions
    add constraint finance_transactions_counter_differs
    check (counter_account_id is null or counter_account_id <> account_id);

create index finance_transactions_account_dt_idx
    on public.finance_transactions (account_id, datetime desc);

create index finance_transactions_counter_idx
    on public.finance_transactions (counter_account_id)
 where counter_account_id is not null;

-- ---------------------------------------------------------------------------
-- 5. 저장된 잔액을 뺀다
-- ---------------------------------------------------------------------------
-- 위 3번에서 개시잔액으로 옮겨졌다. 이 시점 이후로 잔액은 유도값이다.
alter table public.finance_transactions drop column balance;

-- ---------------------------------------------------------------------------
-- 6. 중복 방지 제약을 뺀다
-- ---------------------------------------------------------------------------
-- 원래 주석: "앱이 PDF 재파싱 시 이 조합으로 upsert 한다". 목적이 **PDF 재파싱**
-- 이었고, 그 경로는 한 번도 쓰인 적이 없다 (거래 273건이 전부 수기 이관분이고
-- PDF 로 들어온 건 0건이다).
--
-- 수기 입력에서는 오히려 방해가 된다. 사람은 시각을 고르지 않으므로 같은 날 같은
-- 금액 거래 둘 — 8월 모임통장의 볼링장 결제처럼 — 이 서로를 막는다.
-- 임포트 스크립트가 09:00 부터 1분씩 밀어 피했던 그 문제가 앱에도 온다.
alter table public.finance_transactions
    drop constraint if exists finance_transactions_ledger_id_datetime_amount_key;
