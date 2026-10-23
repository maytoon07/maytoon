-- ============================================================
-- MAYTOON (메이툰) Supabase 초기 테이블 설계
-- Supabase 대시보드 왼쪽 메뉴 "SQL Editor" -> "New query" 에 이 파일
-- 내용을 전부 붙여넣고 "Run" 누르면 한 번에 테이블이 만들어져요.
-- ============================================================

-- 확장 기능 (UUID 자동 생성용)
create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- 1) 회원 프로필 (로그인한 사람 정보 + 하트 잔액)
--    실제 로그인 계정(auth.users)에 1:1로 붙는 테이블
-- ------------------------------------------------------------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nick text not null,
  hearts int not null default 0,
  is_admin boolean not null default false, -- 운영자(나)만 true로 바꿀 것
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2) 크리에이터 신청 (신청 -> 운영자 승인/반려)
-- ------------------------------------------------------------
create table if not exists applications (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  bio text,
  emoji text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  author_id uuid, -- 승인되면 여기에 authors.id 연결
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 3) 크리에이터 (승인된 사람만 생김)
-- ------------------------------------------------------------
create table if not exists authors (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  bio text,
  emoji text,
  color text,
  followers int not null default 0,
  created_at timestamptz not null default now()
);

alter table applications
  add constraint applications_author_id_fkey
  foreign key (author_id) references authors(id) on delete set null;

-- ------------------------------------------------------------
-- 4) 멤버십 플랜 (크리에이터별 구독 단계)
-- ------------------------------------------------------------
create table if not exists plans (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references authors(id) on delete cascade,
  level int not null,            -- 0,1,2 (1단계,2단계,3단계)
  name text not null,
  price int not null,
  perk text,
  member_count int not null default 0,
  unique(author_id, level)
);

-- ------------------------------------------------------------
-- 5) 만화 게시물
-- ------------------------------------------------------------
create table if not exists posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references authors(id) on delete cascade,
  title text not null,
  description text,
  access text not null default 'free' check (access in ('free','plan','paid')),
  plan_level int,                -- access='plan'일 때, 몇 단계 이상 볼 수 있는지
  hearts int,                    -- access='paid'일 때, 가격(하트)
  mem_free_level int,            -- access='paid'인데 이 단계 이상 멤버십이면 무료
  likes int not null default 0,
  cuts jsonb not null default '[]',  -- 이미지 없는 예시 컷 [{e,t}]
  imgs jsonb not null default '[]',  -- 실제 업로드 이미지 URL들 (Storage 연동 후 사용)
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 6) 댓글
-- ------------------------------------------------------------
create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  reader_id uuid references auth.users(id) on delete set null,
  nick text not null,
  body text not null,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 7) 독자 행동 (팔로우 / 멤버십 가입 / 구매 / 좋아요 / 북마크)
-- ------------------------------------------------------------
create table if not exists follows (
  reader_id uuid not null references auth.users(id) on delete cascade,
  author_id uuid not null references authors(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reader_id, author_id)
);

create table if not exists memberships (
  reader_id uuid not null references auth.users(id) on delete cascade,
  author_id uuid not null references authors(id) on delete cascade,
  level int not null,
  created_at timestamptz not null default now(),
  primary key (reader_id, author_id)
);

create table if not exists bought (
  reader_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reader_id, post_id)
);

create table if not exists liked (
  reader_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reader_id, post_id)
);

create table if not exists bookmarks (
  reader_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reader_id, post_id)
);

-- ------------------------------------------------------------
-- 8) 후원 (하트 후원 메시지)
-- ------------------------------------------------------------
create table if not exists tips (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references authors(id) on delete cascade,
  reader_id uuid references auth.users(id) on delete set null,
  nick text,
  hearts int not null,
  msg text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 운영자 확인용 함수 (RLS 정책에서 "나는 운영자인가?" 체크할 때 씀)
-- ============================================================
create or replace function is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;

-- ============================================================
-- RLS(Row Level Security) 켜기 — 꼭 켜야 "남의 데이터"를 못 건드려요
-- ============================================================
alter table profiles      enable row level security;
alter table applications  enable row level security;
alter table authors       enable row level security;
alter table plans         enable row level security;
alter table posts         enable row level security;
alter table comments      enable row level security;
alter table follows       enable row level security;
alter table memberships   enable row level security;
alter table bought        enable row level security;
alter table liked         enable row level security;
alter table bookmarks     enable row level security;
alter table tips          enable row level security;

-- ---- profiles ----
create policy "본인 프로필 보기/운영자는 전체 보기" on profiles
  for select using (auth.uid() = id or is_admin());
create policy "본인 프로필 만들기" on profiles
  for insert with check (auth.uid() = id);
create policy "본인 프로필 수정" on profiles
  for update using (auth.uid() = id);

-- ---- applications (신청) ----
create policy "신청은 누구나 볼 수 있는 목록 아님: 본인+운영자만" on applications
  for select using (auth.uid() = applicant_id or is_admin());
create policy "로그인한 사람은 본인 이름으로 신청 가능" on applications
  for insert with check (auth.uid() = applicant_id);
create policy "본인은 대기중 신청 취소(삭제) 가능" on applications
  for delete using (auth.uid() = applicant_id and status = 'pending');
create policy "운영자만 승인/반려 가능" on applications
  for update using (is_admin());

-- ---- authors (크리에이터 목록, 공개) ----
create policy "크리에이터 목록은 누구나 열람" on authors
  for select using (true);
create policy "운영자만 크리에이터 생성(승인 시)" on authors
  for insert with check (is_admin());
create policy "본인(owner) 또는 운영자만 수정" on authors
  for update using (owner_id = auth.uid() or is_admin());

-- ---- plans (멤버십 플랜, 공개 열람) ----
create policy "플랜은 누구나 열람" on plans
  for select using (true);
create policy "크리에이터 본인만 플랜 관리" on plans
  for insert with check (exists (select 1 from authors a where a.id = author_id and a.owner_id = auth.uid()));
create policy "크리에이터 본인만 플랜 수정" on plans
  for update using (exists (select 1 from authors a where a.id = author_id and a.owner_id = auth.uid()));
create policy "크리에이터 본인만 플랜 삭제" on plans
  for delete using (exists (select 1 from authors a where a.id = author_id and a.owner_id = auth.uid()));

-- ---- posts (만화, 공개 열람 — 실제 잠금은 다음 단계에서 서버 함수로 강화 예정) ----
create policy "만화 목록/내용은 누구나 열람" on posts
  for select using (true);
create policy "크리에이터 본인만 올리기" on posts
  for insert with check (exists (select 1 from authors a where a.id = author_id and a.owner_id = auth.uid()));
create policy "크리에이터 본인만 수정" on posts
  for update using (exists (select 1 from authors a where a.id = author_id and a.owner_id = auth.uid()));
create policy "크리에이터 본인만 삭제" on posts
  for delete using (exists (select 1 from authors a where a.id = author_id and a.owner_id = auth.uid()));

-- ---- comments ----
create policy "댓글은 누구나 열람" on comments
  for select using (true);
create policy "로그인한 사람만 댓글 작성" on comments
  for insert with check (auth.uid() = reader_id);
create policy "본인 댓글만 삭제" on comments
  for delete using (auth.uid() = reader_id);

-- ---- follows / memberships / bought / liked / bookmarks: 전부 "내 것만" ----
create policy "본인 팔로우만 열람" on follows for select using (auth.uid() = reader_id);
create policy "본인 팔로우만 추가" on follows for insert with check (auth.uid() = reader_id);
create policy "본인 팔로우만 삭제" on follows for delete using (auth.uid() = reader_id);

create policy "본인 멤버십만 열람" on memberships for select using (auth.uid() = reader_id);
create policy "본인 멤버십만 추가" on memberships for insert with check (auth.uid() = reader_id);
create policy "본인 멤버십만 삭제" on memberships for delete using (auth.uid() = reader_id);

create policy "본인 구매만 열람" on bought for select using (auth.uid() = reader_id);
create policy "본인 구매만 추가" on bought for insert with check (auth.uid() = reader_id);

create policy "본인 좋아요만 열람" on liked for select using (auth.uid() = reader_id);
create policy "본인 좋아요만 추가" on liked for insert with check (auth.uid() = reader_id);
create policy "본인 좋아요만 삭제" on liked for delete using (auth.uid() = reader_id);

create policy "본인 북마크만 열람" on bookmarks for select using (auth.uid() = reader_id);
create policy "본인 북마크만 추가" on bookmarks for insert with check (auth.uid() = reader_id);
create policy "본인 북마크만 삭제" on bookmarks for delete using (auth.uid() = reader_id);

-- ---- tips (후원) ----
create policy "후원 목록은 누구나 열람" on tips for select using (true);
create policy "로그인한 사람만 후원 작성" on tips for insert with check (auth.uid() = reader_id);
