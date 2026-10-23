-- ============================================================
-- MAYTOON (메이툰) 2차 마이그레이션
-- 목적: 잠긴(멤버십/유료) 만화의 실제 컷/이미지를 "서버에서" 숨기기
--       (지금까지는 화면에만 안 보였을 뿐, 주소를 알면 누구나 볼 수 있었음)
-- Supabase 대시보드 "SQL Editor" -> "New query" 에 전부 붙여넣고 Run.
-- ============================================================

-- 1) 누구나 봐도 되는 "커버 미리보기"용 칼럼을 posts에 추가
--    (카드 목록에 보이는 썸네일/이모지 + 컷수 — 민감하지 않은 정보)
alter table posts add column if not exists cover_e text;
alter table posts add column if not exists cover_img text;
alter table posts add column if not exists cut_count int not null default 1;

-- 2) 실제 컷 내용(cuts/imgs)은 별도 테이블로 분리
--    (RLS는 행 단위로만 걸리기 때문에, 같은 posts 행 안에 있으면
--     "제목은 보이게, 컷은 안 보이게" 가 불가능해서 테이블을 나눔)
create table if not exists post_content (
  post_id uuid primary key references posts(id) on delete cascade,
  cuts jsonb not null default '[]',
  imgs jsonb not null default '[]'
);

-- 3) 기존 posts에 있던 cuts/imgs를 post_content로 옮기고, 커버 정보 채우기
insert into post_content (post_id, cuts, imgs)
select id, coalesce(cuts,'[]'::jsonb), coalesce(imgs,'[]'::jsonb) from posts
on conflict (post_id) do nothing;

update posts set
  cover_img = case when jsonb_array_length(coalesce(imgs,'[]'::jsonb)) > 0 then imgs->>0 else null end,
  cover_e   = case when jsonb_array_length(coalesce(imgs,'[]'::jsonb)) = 0
                     and jsonb_array_length(coalesce(cuts,'[]'::jsonb)) > 0
                    then cuts->0->>'e' else null end,
  cut_count = greatest(jsonb_array_length(coalesce(imgs,'[]'::jsonb)), jsonb_array_length(coalesce(cuts,'[]'::jsonb)), 1);

-- 4) posts에서 실제 컷 데이터 칼럼 제거 (이제 post_content에만 있음)
alter table posts drop column if exists cuts;
alter table posts drop column if exists imgs;

-- 5) post_content는 RLS로 "볼 수 있는 사람만" 허용
alter table post_content enable row level security;

-- 이 만화를 "볼 수 있는지" 서버에서 판단하는 함수
-- (free/본인작품/운영자/멤버십 단계/구매 여부를 전부 체크)
create or replace function can_see_post(pid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when p.access = 'free' then true
    when a.owner_id = auth.uid() then true
    when is_admin() then true
    when p.access = 'plan' then exists(
      select 1 from memberships m
      where m.reader_id = auth.uid() and m.author_id = p.author_id and m.level >= p.plan_level
    )
    when p.access = 'paid' then
      exists(select 1 from bought b where b.reader_id = auth.uid() and b.post_id = p.id)
      or (p.mem_free_level is not null and exists(
        select 1 from memberships m
        where m.reader_id = auth.uid() and m.author_id = p.author_id and m.level >= p.mem_free_level - 1
      ))
    else false
  end
  from posts p join authors a on a.id = p.author_id
  where p.id = pid
$$;

create policy "볼 수 있는 사람만 컷 열람" on post_content
  for select using (can_see_post(post_id));

create policy "크리에이터 본인만 컷 추가" on post_content
  for insert with check (
    exists(select 1 from posts p join authors a on a.id = p.author_id
           where p.id = post_id and a.owner_id = auth.uid())
  );

create policy "크리에이터 본인만 컷 수정" on post_content
  for update using (
    exists(select 1 from posts p join authors a on a.id = p.author_id
           where p.id = post_id and a.owner_id = auth.uid())
  );

create policy "크리에이터 본인만 컷 삭제" on post_content
  for delete using (
    exists(select 1 from posts p join authors a on a.id = p.author_id
           where p.id = post_id and a.owner_id = auth.uid())
  );
