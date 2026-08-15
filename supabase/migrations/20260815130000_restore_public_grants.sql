-- public 스키마 재생성으로 사라진 권한 복구
--
-- 무슨 일이 있었나
--   20260813120000 이 `drop schema public cascade` 를 하면서, Supabase가 프로젝트
--   생성 시 public 스키마에 걸어두는 두 가지가 같이 날아갔다.
--     1. 기존 테이블에 대한 anon/authenticated/service_role 의 테이블 권한
--     2. 앞으로 만들 객체에 그 권한을 자동으로 붙여주는 ALTER DEFAULT PRIVILEGES
--   그 마이그레이션은 스키마 USAGE 만 다시 줬기 때문에, 이후 만들어진 모든 테이블에
--   아무도 권한이 없는 상태가 됐다.
--
-- 증상
--   앱(authenticated)·워커(service_role) 모두 "42501 permission denied for table ..." 를
--   받는다. RLS 정책이 아무리 맞게 걸려 있어도 소용없다. 권한 검사가 RLS보다 먼저다.
--
-- 주의
--   anon 에도 Supabase 기본값대로 권한을 준다. 이건 **모든 테이블에 RLS가 켜져 있다**는
--   전제 위에 서 있다. RLS를 안 켠 테이블을 public 스키마에 추가하는 순간 그 테이블은
--   anon key 만으로 읽힌다. anon key 는 앱 바이너리에 노출되어 있다.
--   새 테이블을 만들면 반드시 `alter table ... enable row level security` 를 같이 쓸 것.

grant usage on schema public to postgres, anon, authenticated, service_role;

-- 지금 있는 객체들
grant all on all tables    in schema public to postgres, anon, authenticated, service_role;
grant all on all routines  in schema public to postgres, anon, authenticated, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;

-- 앞으로 만들 객체들
alter default privileges for role postgres in schema public
    grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
    grant all on routines to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
    grant all on sequences to postgres, anon, authenticated, service_role;
