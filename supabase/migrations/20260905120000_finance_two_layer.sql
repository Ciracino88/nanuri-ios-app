-- 재정 스키마 2층 재설계 — 은행 증명(거래) vs 장부(항목)
--
-- 왜 갈아엎나
--   지금까지 `finance_transactions` 는 "통장에 찍힌 줄"을 담되, 농협 수기 입력을
--   `source=manual` 로 같은 표에 넣어 왔다. 그런데 이 표는 태생이 **은행의 기록**이라
--   금액·일시·통장을 잠근다. 농협 수기는 은행이 증명하지 않은 값을 그 표에 **은행
--   기록인 척** 넣는 위장이었다. `source` 컬럼 하나가 그 위장을 표시할 뿐이었다.
--
--   그래서 신뢰수준을 **표로** 가른다.
--     거래(finance_transactions) = 은행이 증명한 사실. 토스 내역서 파싱으로만 생성,
--                                  불변(INSERT/DELETE 만). 실질적으로 모임통장만.
--     항목(finance_items)        = 장부 정본, 사람의 판단. 잔액·보고서가 여기서 나온다.
--                                  1급 엔티티라 자기 통장·시각·금액을 스스로 갖는다.
--
--   항목의 `source_transaction_id` 유무가 곧 신뢰수준이다 —
--     차 있으면 → 은행 증명이 뒤에 있음(모임 내역서 줄). 금액합·일시·통장 잠금.
--     비어 있으면 → 농협 수기. 사람의 말뿐이라 전부 편집 가능.
--
-- 데이터
--   원본 장부는 엑셀에 있어 **재삽입한다**(bills 는 안 건드린다). 그래서 기존 finance_*
--   데이터는 버리고 표를 새로 세운다.
--
-- 보안 전제는 20260813120000_reset_schema.sql 과 같다 — 모든 정책은
-- public.admins 화이트리스트(is_admin())를 기준으로 하고, 모든 표에 RLS 를 켠다.
-- 권한은 20260815130000 의 alter default privileges 가 새 표에도 자동으로 붙인다.

-- ---------------------------------------------------------------------------
-- 0. 옛 표를 버린다
-- ---------------------------------------------------------------------------
-- 의존 순서대로 지운다. cascade 로 걸린 인덱스·정책·FK 도 같이 사라진다.
-- finance_ledgers 를 지우면 그걸 참조하던 accounts·transactions 가 cascade 로 함께
-- 지워지지만, 아래에서 전부 새로 세우므로 순서만 지키면 된다.
drop table if exists public.finance_splits       cascade;
drop table if exists public.finance_transactions cascade;
drop table if exists public.finance_accounts     cascade;
drop table if exists public.finance_ledgers      cascade;   -- ⑥ 장부 개념 폐기

-- ---------------------------------------------------------------------------
-- 1. 통장 — 2개 고정 (농협·모임)
-- ---------------------------------------------------------------------------
-- 장부(`ledger_id`)를 더는 참조하지 않는다. 장부가 하나뿐이라 고를 것이 없어
-- 개념째 없앴다. 통장은 실제 은행 계좌라 개수가 현실에 묶여 있고, 이 앱에서는
-- 농협(헌금)·모임(토스 실시간 처리) 둘로 고정이다.
create table public.finance_accounts (
    id              uuid        primary key default gen_random_uuid(),

    -- 화면용 별명. 목록·잔액·이체 방향("농협 → 모임")에 나온다.
    name            text        not null unique,

    -- 이 통장의 예금주 이름. 은행이 상대 통장 내역서 적요에 찍는 값이다.
    -- 내부이체 판정에 쓴다: 내역서 적요 == 다른 통장의 holder_name 이면 그 통장과
    -- 주고받은 것이다. 농협='예수교대한성결고천교'. 모임은 농협 내역서가 없어(인터넷
    -- 뱅킹 없음) 쓸 자리가 없으므로 비워 둔다.
    holder_name     text,

    -- 장부가 이 통장을 적기 시작하는 시점에 이미 들어 있던 돈.
    -- 통장 잔액 = opening_balance + 그 통장 항목들의 누적. (엑셀 재삽입 때 채운다)
    opening_balance integer     not null default 0,

    sort_order      integer     not null default 0,   -- 화면 순서
    created_at      timestamptz not null default now()
);

alter table public.finance_accounts enable row level security;

create policy "관리자 전용 통장" on public.finance_accounts
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());

-- 통장 두 개를 심는다. opening_balance 는 엑셀 재삽입이 채운다(농협 전월이월, 모임 0).
insert into public.finance_accounts (name, holder_name, sort_order) values
    ('농협', '예수교대한성결고천교', 1),
    ('모임',  null,                  2);

-- ---------------------------------------------------------------------------
-- 2. 거래 — 은행 증명 (파싱으로만 생성, 불변)
-- ---------------------------------------------------------------------------
-- 토스 거래내역서 한 줄이 곧 이 표의 한 행이다. **은행이 말한 사실**이라 절대
-- 편집하지 않는다(INSERT/DELETE 만). 영수증·카테고리·적요(사람 값)는 여기 없다 —
-- 그건 전부 항목(finance_items)으로 갔다.
--
-- 중복 방지 제약을 두지 않는다. 같은 초에 찍힌 동일 금액 카드결제 둘이 서로를
-- 막을 수 있어서다. 같은 내역서를 두 번 불러올 때의 중복은 앱이 막는다
-- (StatementMatcher 의 alreadyImported: 금액 + 1초 이내 시각).
create table public.finance_transactions (
    id          uuid        primary key default gen_random_uuid(),

    -- 실질적으로 늘 모임이지만, 일반화해 둔다.
    account_id  uuid        not null references public.finance_accounts(id) on delete restrict,

    datetime    timestamptz not null,     -- 은행이 찍은 시각
    type        text        not null,     -- 은행 유형(이자입금·체크카드결제·ATM출금…)
    amount      integer     not null,     -- 은행이 말한 총액(부호). 대조의 기준
    description text,                      -- 은행 적요(예금주·가맹점)
    created_at  timestamptz not null default now()
);

create index finance_transactions_account_dt_idx
    on public.finance_transactions (account_id, datetime desc);

alter table public.finance_transactions enable row level security;

create policy "관리자 전용 거래" on public.finance_transactions
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- 3. 항목 — 장부 정본 (사람의 판단, 구 finance_splits)
-- ---------------------------------------------------------------------------
-- 잔액·보고서·그래프가 전부 여기서 나온다. 구 finance_splits 를 개명·승격한 것이라
-- "거래의 분할"이 아니라 **장부 그 자체**다. 그래서 부모 거래에 매달리지 않고
-- 자기 통장·시각·금액을 스스로 갖는다(농협 항목엔 뒤에 거래가 없다).
create table public.finance_items (
    id                    uuid        primary key default gen_random_uuid(),

    account_id            uuid        not null references public.finance_accounts(id) on delete restrict,
    datetime              timestamptz not null,   -- 모임 항목은 거래 시각을 복사, 농협은 자기 시각
    amount                integer     not null,   -- 부호(음수=출금). 잔액·보고서의 원천

    -- 통장 사이 이체 표식. **상대는 늘 '다른 통장 하나'** 라(통장 2개 고정) 어느
    -- 통장인지 따로 안 적는다. 이 값이 참이면 잔액 유도에서 상대 통장에 부호를
    -- 뒤집어 반영하고, 보고서·합계·그래프에서는 제외한다(수입도 지출도 아니므로).
    -- 판정은 불러올 때 매처가 한다(적요 == 다른 통장의 holder_name).
    is_internal_transfer  boolean     not null default false,

    category              text,                   -- 사람 판단
    description           text,                   -- 사람이 적는 적요

    -- 이 항목에 딸린 영수증. 매칭 때 대응 청구의 receipt_url 을 **복사**해 온다
    -- (박제 — 청구를 지워도 장부 영수증이 흔들리지 않는다). 농협 수기 항목은 사람이
    -- 사진을 붙이면 여기 담긴다. 영수증 부록 PDF 는 이 컬럼을 모아 만든다.
    receipt_urls          text[]      not null default '{}',

    -- 이 항목이 나온 은행 거래. **차 있으면 은행 증명 뒤에 있음(모임), 비어 있으면
    -- 농협 수기.** 이게 신뢰수준의 표식이자 편집 잠금의 근거다. 거래를 지우면 그
    -- 거래에서 나온 항목들도 함께 지운다(불러오기 되돌리기 = cascade).
    source_transaction_id uuid        references public.finance_transactions(id) on delete cascade,

    sort_order            integer     not null default 0,   -- 한 거래 아래 항목들의 순서
    created_at            timestamptz not null default now()
);

create index finance_items_account_dt_idx
    on public.finance_items (account_id, datetime desc);

-- 대조(Σ 항목 == 거래.amount)와 조각 나열에 쓴다.
create index finance_items_source_idx
    on public.finance_items (source_transaction_id, sort_order)
 where source_transaction_id is not null;

-- 보고서·합계는 이체를 뺀 실제 수입·지출만 센다. 그 걸러내기를 인덱스가 돕는다.
create index finance_items_external_idx
    on public.finance_items (datetime desc)
 where is_internal_transfer = false;

alter table public.finance_items enable row level security;

create policy "관리자 전용 항목" on public.finance_items
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());
