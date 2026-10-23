-- ============================================================
-- MAYTOON (메이툰) 3차 마이그레이션
-- 목적: 만화 이미지를 DB(post_content.imgs)에 base64 텍스트로 직접
--       저장하던 것을 "Supabase Storage" 실제 파일로 옮기기
--       (DB 무료 용량 500MB를 이미지가 다 써버리는 걸 막기 위함)
-- Supabase 대시보드 "SQL Editor" -> "New query" 에 전부 붙여넣고 Run.
-- ============================================================

-- 1) 이미지 저장용 버킷 생성 (비공개 — 볼 수 있는 사람만 꺼내볼 수 있게)
insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', false)
on conflict (id) do nothing;

alter table storage.objects enable row level security;

-- 2) "볼 수 있는 사람만 이 이미지를 꺼내볼 수 있다" — post_content와 똑같은 규칙(can_see_post) 적용
--    이미지는 "<만화id>/0.jpg", "<만화id>/1.jpg" ... 형태의 경로로 저장할 거라
--    경로의 첫 폴더(만화id)로 can_see_post()를 체크함
create policy "볼 수 있는 사람만 이미지 다운로드"
on storage.objects for select
using (
  bucket_id = 'post-images'
  and can_see_post((storage.foldername(name))[1]::uuid)
);

-- 3) 크리에이터 본인만 자기 만화 폴더에 이미지 업로드/수정/삭제 가능
create policy "크리에이터 본인만 이미지 업로드"
on storage.objects for insert
with check (
  bucket_id = 'post-images'
  and exists(
    select 1 from posts p join authors a on a.id = p.author_id
    where p.id = (storage.foldername(name))[1]::uuid and a.owner_id = auth.uid()
  )
);

create policy "크리에이터 본인만 이미지 수정"
on storage.objects for update
using (
  bucket_id = 'post-images'
  and exists(
    select 1 from posts p join authors a on a.id = p.author_id
    where p.id = (storage.foldername(name))[1]::uuid and a.owner_id = auth.uid()
  )
);

create policy "크리에이터 본인만 이미지 삭제"
on storage.objects for delete
using (
  bucket_id = 'post-images'
  and exists(
    select 1 from posts p join authors a on a.id = p.author_id
    where p.id = (storage.foldername(name))[1]::uuid and a.owner_id = auth.uid()
  )
);

-- ※ 참고: 이 마이그레이션 이전에 이미 올라간 만화(이미지가 post_content.imgs 안에
--   base64 텍스트로 들어있는 것들)는 그대로 둬도 괜찮아요 — 사이트 코드가 "이게
--   base64인지 Storage 경로인지" 자동으로 구분해서 예전 데이터도 계속 잘 보여줘요.
--   다만 그 데이터는 여전히 DB 용량을 차지하니, 여유 있을 때 새로 다시 올리는 걸 권장.
