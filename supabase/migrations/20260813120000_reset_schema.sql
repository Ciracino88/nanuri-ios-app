-- 나누리 관리자 앱 스키마 전면 재설계
--
-- 전제
--   * 관리자 1인 전용 앱. auth.users에는 관리자 계정만 존재한다.
--   * 멤버용 웹은 폐지. 청구서는 카카오 챗봇 → Worker(service_role)로만 들어온다.
--   * 청구자의 이름·은행·계좌는 청구 시점 값을 bills에 그대로 박제한다.
--
-- 보안 전제 (중요)
--   anon key는 앱 바이너리에 노출되어 있고 Google provider는 임의의 구글 계정을
--   로그인시킨다. 따라서 "authenticated"만으로는 보호가 되지 않는다.
--   모든 정책은 public.admins 화이트리스트(is_admin())를 기준으로 한다.

-- ---------------------------------------------------------------------------
-- 0. 초기화
-- ---------------------------------------------------------------------------
-- 주의: public 스키마의 모든 객체(과거 설문 테이블 등 포함)를 삭제한다.
-- 확장(extension)은 Supabase가 extensions 스키마에 두므로 영향받지 않는다.
drop schema public cascade;
create schema public;

grant usage on schema public to anon, authenticated, service_role;
grant all on schema public to postgres, service_role;

-- ---------------------------------------------------------------------------
-- 1. 관리자 화이트리스트
-- ---------------------------------------------------------------------------
create table public.admins (
    email      text primary key,
    created_at timestamptz not null default now()
);

insert into public.admins (email) values ('ciracino88@gmail.com');

-- admins 자신은 RLS로 잠그고, 아래 security definer 함수로만 조회한다.
alter table public.admins enable row level security;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.admins
        where email = lower(auth.jwt() ->> 'email')
    );
$$;

grant execute on function public.is_admin() to authenticated;

-- 화이트리스트 밖 계정은 가입 자체를 차단하고, 관리자면 프로필 행을 만들어 둔다.
-- (앱의 프로필 저장은 UPDATE만 하므로 행이 미리 있어야 한다)
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from public.admins where email = lower(new.email)) then
        raise exception '관리자 계정이 아닙니다: %', new.email;
    end if;

    insert into public.profiles (id, name)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'full_name',
                 new.raw_user_meta_data ->> 'name',
                 '')
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 2. 프로필 (관리자 본인)
-- ---------------------------------------------------------------------------
create table public.profiles (
    id             uuid primary key references auth.users(id) on delete cascade,
    name           text        not null default '',
    bank_name      text,
    account_number text,
    position       text[]      not null default '{}',   -- 예배 포지션
    avatar_url     text,
    updated_at     timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "관리자는 본인 프로필 조회" on public.profiles
    for select to authenticated
    using (id = auth.uid() and public.is_admin());

create policy "관리자는 본인 프로필 수정" on public.profiles
    for update to authenticated
    using (id = auth.uid() and public.is_admin())
    with check (id = auth.uid() and public.is_admin());

-- ---------------------------------------------------------------------------
-- 3. 청구서
-- ---------------------------------------------------------------------------
-- 청구자 정보는 조인 없이 행 안에 박제한다. 멤버가 나중에 계좌를 바꿔도
-- 과거 청구서의 송금 기록이 흔들리지 않는다.
create table public.bills (
    id             uuid        primary key default gen_random_uuid(),
    created_at     timestamptz not null default now(),

    title          text        not null,
    amount         integer     not null check (amount > 0),

    submitter_name text        not null,
    bank_name      text        not null,
    account_number text        not null,

    receipt_url    text,                                  -- 챗봇 경로에선 없을 수 있음
    note           text,

    status         text        not null default 'pending'
                   check (status in ('pending', 'approved', 'rejected')),
    processed_at   timestamptz,

    kakao_user_id  text                                   -- 카카오 발신자 식별용
);

create index bills_status_created_idx on public.bills (status, created_at desc);

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
create function public.touch_bill_processed_at()
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

-- 앱이 Realtime으로 구독한다.
alter publication supabase_realtime add table public.bills;

-- ---------------------------------------------------------------------------
-- 4. 재정 — 장부
-- ---------------------------------------------------------------------------
create table public.finance_ledgers (
    id         uuid        primary key default gen_random_uuid(),
    name       text        not null,
    type       text        not null check (type in ('monthly', 'event')),
    created_at timestamptz not null default now()
);

alter table public.finance_ledgers enable row level security;

create policy "관리자 전용 장부" on public.finance_ledgers
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- 5. 재정 — 거래
-- ---------------------------------------------------------------------------
create table public.finance_transactions (
    id           uuid        primary key default gen_random_uuid(),
    ledger_id    uuid        not null references public.finance_ledgers(id) on delete cascade,

    datetime     timestamptz not null,
    type         text        not null,
    amount       integer     not null,      -- 출금은 음수
    balance      integer     not null,
    description  text,

    category     text,
    memo         text,
    receipt_urls text[]      not null default '{}',
    created_at   timestamptz not null default now(),

    -- 앱이 PDF 재파싱 시 이 조합으로 upsert 한다 (onConflict). 중복 취임 방지.
    unique (ledger_id, datetime, amount)
);

create index finance_transactions_ledger_dt_idx
    on public.finance_transactions (ledger_id, datetime desc);

alter table public.finance_transactions enable row level security;

create policy "관리자 전용 거래" on public.finance_transactions
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- 6. 재정 — 거래 분할
-- ---------------------------------------------------------------------------
create table public.finance_splits (
    id             uuid    primary key default gen_random_uuid(),
    transaction_id uuid    not null references public.finance_transactions(id) on delete cascade,
    amount         integer not null,
    category       text,
    memo           text,
    sort_order     integer not null default 0
);

create index finance_splits_tx_idx on public.finance_splits (transaction_id, sort_order);

alter table public.finance_splits enable row level security;

create policy "관리자 전용 분할" on public.finance_splits
    for all to authenticated
    using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- 7. APNs 디바이스 토큰
-- ---------------------------------------------------------------------------
create table public.device_tokens (
    token       text        primary key,
    user_id     uuid        not null references auth.users(id) on delete cascade,
    environment text        not null default 'production'
                check (environment in ('sandbox', 'production')),
    updated_at  timestamptz not null default now()
);

alter table public.device_tokens enable row level security;

create policy "관리자는 본인 토큰 관리" on public.device_tokens
    for all to authenticated
    using (user_id = auth.uid() and public.is_admin())
    with check (user_id = auth.uid() and public.is_admin());

-- ---------------------------------------------------------------------------
-- 8. Storage — 아바타
-- ---------------------------------------------------------------------------
-- 앱이 getPublicURL을 쓰므로 공개 읽기 버킷이어야 한다.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "아바타 공개 읽기" on storage.objects;
create policy "아바타 공개 읽기" on storage.objects
    for select to public
    using (bucket_id = 'avatars');

drop policy if exists "관리자는 본인 폴더에 아바타 업로드" on storage.objects;
create policy "관리자는 본인 폴더에 아바타 업로드" on storage.objects
    for all to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
        and public.is_admin()
    )
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
        and public.is_admin()
    );
