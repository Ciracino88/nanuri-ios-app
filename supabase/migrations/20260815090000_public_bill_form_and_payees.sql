-- 청구 접수 경로 교체: 카카오 챗봇 → 공개 웹페이지
--
-- 바뀐 점
--   * 폼이 공개 URL이 되면서 발신자를 식별할 수 없다. kakao_user_id를 없앤다.
--   * 웹에서 받는 값은 이름·제목·금액·영수증 네 가지뿐이다.
--     청구자가 은행·계좌를 직접 입력하지 않는다.
--   * 대신 관리자가 앱에서 이름↔계좌를 payees에 등록해 두고,
--     들어온 청구서의 이름을 대조해 계좌를 찾는다.
--   * 기존 bills 데이터는 버린다.
--
-- 보안 전제는 20260813120000_reset_schema.sql 과 같다.
-- 모든 정책은 public.admins 화이트리스트(is_admin())를 기준으로 한다.

-- ---------------------------------------------------------------------------
-- 0. 이미 가입돼 있는 관리자의 프로필 행 backfill
-- ---------------------------------------------------------------------------
-- handle_new_user 트리거는 auth.users INSERT 때만 돈다. 앞 마이그레이션이
-- public 스키마를 통째로 재생성하면서 profiles가 비었으므로, 이미 가입한
-- 관리자 계정은 프로필 행이 없는 상태가 된다. 앱의 프로필 저장은 UPDATE만
-- 하기 때문에 행이 없으면 조용히 실패한다.
insert into public.profiles (id, name)
select u.id,
       coalesce(u.raw_user_meta_data ->> 'full_name',
                u.raw_user_meta_data ->> 'name',
                '')
from auth.users u
join public.admins a on a.email = lower(u.email)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 1. 계좌부 (이름 ↔ 입금 계좌)
-- ---------------------------------------------------------------------------
create table if not exists public.payees (
    id             uuid        primary key default gen_random_uuid(),
    name           text        not null,
    bank_name      text        not null,
    account_number text        not null,
    memo           text,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

-- 청구서의 이름과 대조할 때 공백·대소문자를 무시한다.
-- "홍길동", "홍 길동", "홍길동 " 이 모두 같은 사람으로 잡혀야 한다.
-- 앱의 String.normalizedName 과 규칙이 반드시 같아야 한다.
create unique index if not exists payees_name_normalized_idx
    on public.payees (lower(regexp_replace(name, '\s', '', 'g')));

alter table public.payees enable row level security;

drop policy if exists "관리자 전용 계좌부" on public.payees;
create policy "관리자 전용 계좌부" on public.payees
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());

create or replace function public.touch_payee_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists payees_touch_updated_at on public.payees;
create trigger payees_touch_updated_at
    before update on public.payees
    for each row execute function public.touch_payee_updated_at();

-- ---------------------------------------------------------------------------
-- 2. 청구서 재생성
-- ---------------------------------------------------------------------------
-- cascade 는 이 테이블에 걸린 트리거와 realtime publication 등록도 함께 지운다.
-- 아래에서 다시 만들어 준다.
drop table if exists public.bills cascade;

create table public.bills (
    id             uuid        primary key default gen_random_uuid(),
    created_at     timestamptz not null default now(),

    -- 공개 폼에서 받는 네 가지 값
    submitter_name text        not null,
    title          text        not null,
    amount         integer     not null check (amount > 0),
    receipt_url    text        not null,

    status         text        not null default 'pending'
                   check (status in ('pending', 'approved', 'rejected')),
    processed_at   timestamptz
);

create index bills_status_created_idx on public.bills (status, created_at desc);

-- 이름으로 계좌부를 찾을 때 쓴다. payees 쪽 인덱스와 같은 정규화 규칙.
create index bills_submitter_normalized_idx
    on public.bills (lower(regexp_replace(submitter_name, '\s', '', 'g')));

alter table public.bills enable row level security;

-- INSERT 정책은 일부러 두지 않는다. 삽입은 Worker의 service_role만 가능하다.
create policy "관리자는 청구서 조회" on public.bills
    for select to authenticated using (public.is_admin());

create policy "관리자는 청구서 상태 변경" on public.bills
    for update to authenticated
    using (public.is_admin()) with check (public.is_admin());

create policy "관리자는 청구서 삭제" on public.bills
    for delete to authenticated using (public.is_admin());

-- 상태가 바뀐 시점 기록
create or replace function public.touch_bill_processed_at()
returns trigger
language plpgsql
as $$
begin
    if new.status is distinct from old.status then
        new.processed_at := case when new.status = 'pending' then null else now() end;
    end if;
    return new;
end;
$$;

create trigger bills_touch_processed_at
    before update on public.bills
    for each row execute function public.touch_bill_processed_at();

-- 앱이 Realtime으로 구독한다. (drop table 로 빠졌으므로 다시 넣는다)
alter publication supabase_realtime add table public.bills;
