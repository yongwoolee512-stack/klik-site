-- ============================================================
-- 딸깍(Klik) 커뮤니티 1차 — Supabase 테이블·보안 규칙
-- 사용법: Supabase 대시보드 → 왼쪽 "SQL Editor" → "New query" →
--         이 파일 내용을 전부 붙여넣고 → 오른쪽 아래 "Run" 클릭.
--         (여러 번 실행해도 안전합니다: 이미 있으면 건너뜁니다)
-- 원칙: 누구나 읽기 가능 / 쓰기는 "추가"만 가능 / 수정·삭제는 아무도 못 함
--       로그인 없음. 브라우저마다 받는 고유 토큰(client)으로 1회 제한.
-- ============================================================

-- 1) 딸깍 설치 클릭 기록 (주간 랭킹용) ---------------------------
create table if not exists public.installs (
  id         bigint generated always as identity primary key,
  tool_id    text not null check (char_length(tool_id) between 1 and 80),
  client     text not null check (char_length(client) between 8 and 64),
  created_at timestamptz not null default now()
);
create index if not exists installs_tool_time on public.installs (tool_id, created_at desc);
alter table public.installs enable row level security;
drop policy if exists "installs_read"   on public.installs;
drop policy if exists "installs_insert" on public.installs;
create policy "installs_read"   on public.installs for select to anon, authenticated using (true);
create policy "installs_insert" on public.installs for insert to anon, authenticated with check (true);

create or replace view public.installs_week with (security_invoker = true) as
  select tool_id, count(*)::int as n
  from public.installs
  where created_at > now() - interval '7 days'
  group by tool_id;

-- 2) 별점(1~5) + 한 줄 평 + 닉네임 (브라우저별 도구당 1회) -----------
create table if not exists public.reviews (
  id         bigint generated always as identity primary key,
  tool_id    text not null check (char_length(tool_id) between 1 and 80),
  client     text not null check (char_length(client) between 8 and 64),
  nick       text not null default '' check (char_length(nick) <= 12),
  stars      smallint not null check (stars between 1 and 5),
  body       text not null default '' check (char_length(body) <= 120),
  likes      integer not null default 0,
  hidden     boolean not null default false,
  created_at timestamptz not null default now(),
  unique (tool_id, client)
);
create index if not exists reviews_tool_rank on public.reviews (tool_id, likes desc, created_at desc);
alter table public.reviews enable row level security;
drop policy if exists "reviews_read"   on public.reviews;
drop policy if exists "reviews_insert" on public.reviews;
create policy "reviews_read"   on public.reviews for select to anon, authenticated using (hidden = false);
create policy "reviews_insert" on public.reviews for insert to anon, authenticated
  with check (likes = 0 and hidden = false);

create or replace view public.review_stats with (security_invoker = true) as
  select tool_id, count(*)::int as n, round(avg(stars)::numeric, 1)::float as avg
  from public.reviews where hidden = false
  group by tool_id;

-- 2-1) 한 줄 평 추천 (브라우저별 평당 1회). 추천 수는 서버가 세어 reviews.likes에 반영
create table if not exists public.review_likes (
  id         bigint generated always as identity primary key,
  review_id  bigint not null references public.reviews (id) on delete cascade,
  client     text not null check (char_length(client) between 8 and 64),
  created_at timestamptz not null default now(),
  unique (review_id, client)
);
alter table public.review_likes enable row level security;
drop policy if exists "review_likes_insert" on public.review_likes;
create policy "review_likes_insert" on public.review_likes for insert to anon, authenticated with check (true);

create or replace function public.review_likes_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.reviews set likes = (select count(*) from public.review_likes where review_id = new.review_id)
   where id = new.review_id;
  return new;
end $$;
drop trigger if exists review_likes_count on public.review_likes;
create trigger review_likes_count after insert on public.review_likes
  for each row execute function public.review_likes_count();

-- 3) "써 봤어요 / 설치 막혔어요" (브라우저별 도구당 종류별 1회, 막힌 사연 한 줄 선택) ----
create table if not exists public.reactions (
  id         bigint generated always as identity primary key,
  tool_id    text not null check (char_length(tool_id) between 1 and 80),
  client     text not null check (char_length(client) between 8 and 64),
  kind       text not null check (kind in ('tried', 'blocked')),
  nick       text not null default '' check (char_length(nick) <= 12),
  note       text not null default '' check (char_length(note) <= 120),
  created_at timestamptz not null default now(),
  unique (tool_id, client, kind)
);
alter table public.reactions enable row level security;
drop policy if exists "reactions_read"   on public.reactions;
drop policy if exists "reactions_insert" on public.reactions;
create policy "reactions_read"   on public.reactions for select to anon, authenticated using (true);
create policy "reactions_insert" on public.reactions for insert to anon, authenticated with check (true);

create or replace view public.reaction_counts with (security_invoker = true) as
  select tool_id,
         count(*) filter (where kind = 'tried')::int   as tried,
         count(*) filter (where kind = 'blocked')::int as blocked
  from public.reactions
  group by tool_id;

-- 4) 댓글 (로그인 없이 닉네임) --------------------------------------
create table if not exists public.comments (
  id         bigint generated always as identity primary key,
  tool_id    text not null check (char_length(tool_id) between 1 and 80),
  client     text not null check (char_length(client) between 8 and 64),
  nick       text not null default '' check (char_length(nick) <= 12),
  body       text not null check (char_length(body) between 1 and 500),
  hidden     boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists comments_tool_time on public.comments (tool_id, created_at desc);
alter table public.comments enable row level security;
drop policy if exists "comments_read"   on public.comments;
drop policy if exists "comments_insert" on public.comments;
create policy "comments_read"   on public.comments for select to anon, authenticated using (hidden = false);
create policy "comments_insert" on public.comments for insert to anon, authenticated with check (hidden = false);

-- 5) 신고 (브라우저별 1회, 3회 쌓이면 자동 숨김). 평·댓글 둘 다 대상 -----
create table if not exists public.reports (
  id         bigint generated always as identity primary key,
  target     text not null check (target in ('review', 'comment')),
  target_id  bigint not null,
  client     text not null check (char_length(client) between 8 and 64),
  created_at timestamptz not null default now(),
  unique (target, target_id, client)
);
alter table public.reports enable row level security;
drop policy if exists "reports_insert" on public.reports;
create policy "reports_insert" on public.reports for insert to anon, authenticated with check (true);
-- 신고 내용은 아무도 읽지 못함 (대시보드 Table Editor에서만 확인)

create or replace function public.reports_auto_hide()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.reports where target = new.target and target_id = new.target_id;
  if n >= 3 then
    if new.target = 'comment' then update public.comments set hidden = true where id = new.target_id;
    else update public.reviews set hidden = true where id = new.target_id; end if;
  end if;
  return new;
end $$;
drop trigger if exists reports_auto_hide on public.reports;
create trigger reports_auto_hide after insert on public.reports
  for each row execute function public.reports_auto_hide();

-- 6) 권한 --------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert on public.installs, public.reviews, public.reactions, public.comments to anon, authenticated;
grant insert on public.review_likes, public.reports to anon, authenticated;
grant select on public.installs_week, public.review_stats, public.reaction_counts to anon, authenticated;
-- 끝. "Success. No rows returned" 가 나오면 성공입니다.
