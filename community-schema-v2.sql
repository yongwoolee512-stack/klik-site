-- ============================================================
-- 딸깍(Klik) 커뮤니티 2차 — 답글 · 질문 광장 · "저도요" · 해결 표시 · 활동 피드
-- 사용법: community-schema.sql 을 먼저 실행한 뒤, 이 파일을 SQL Editor에 붙여넣고 Run.
--         (여러 번 실행해도 안전합니다)
-- 원칙은 1차와 같습니다: 누구나 읽기 / 추가만 가능 / 수정·삭제 불가.
--         "해결됨" 표시만 예외인데, 글쓴이 본인(같은 브라우저 토큰)이 고른 답글만 서버가 기록합니다.
-- ============================================================

-- 1) 질문 광장 ("뭐 쓰면 돼요?") -------------------------------------
create table if not exists public.questions (
  id              bigint generated always as identity primary key,
  tool_id         text check (tool_id is null or char_length(tool_id) between 1 and 80),  -- 카드에서 물으면 도구 id, 광장이면 null
  client          text not null check (char_length(client) between 8 and 64),
  nick            text not null default '' check (char_length(nick) <= 12),
  body            text not null check (char_length(body) between 2 and 300),
  solved_reply_id bigint,
  hidden          boolean not null default false,
  created_at      timestamptz not null default now()
);
create index if not exists questions_time on public.questions (created_at desc);
create index if not exists questions_tool on public.questions (tool_id, created_at desc);
alter table public.questions enable row level security;
drop policy if exists "questions_read"   on public.questions;
drop policy if exists "questions_insert" on public.questions;
create policy "questions_read"   on public.questions for select to anon, authenticated using (hidden = false);
create policy "questions_insert" on public.questions for insert to anon, authenticated with check (hidden = false and solved_reply_id is null);

-- 2) 답글 (댓글·막힌 사연·질문 어디에나) ---------------------------------
create table if not exists public.replies (
  id         bigint generated always as identity primary key,
  target     text not null check (target in ('comment', 'story', 'question')),
  target_id  bigint not null,
  tool_id    text check (tool_id is null or char_length(tool_id) between 1 and 80),  -- 부모 글의 도구 (상세 창에서 한 번에 불러오기용)
  rec_tool   text check (rec_tool is null or char_length(rec_tool) between 1 and 80), -- "이 도구 써 보세요" 추천 카드
  client     text not null check (char_length(client) between 8 and 64),
  nick       text not null default '' check (char_length(nick) <= 12),
  body       text not null check (char_length(body) between 1 and 500),
  hidden     boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists replies_target on public.replies (target, target_id, created_at);
create index if not exists replies_tool   on public.replies (tool_id, created_at);
alter table public.replies enable row level security;
drop policy if exists "replies_read"   on public.replies;
drop policy if exists "replies_insert" on public.replies;
create policy "replies_read"   on public.replies for select to anon, authenticated using (hidden = false);
create policy "replies_insert" on public.replies for insert to anon, authenticated with check (hidden = false);

-- 3) "저도 막혔어요" (사연당 브라우저별 1회) -----------------------------
alter table public.reactions add column if not exists solved_reply_id bigint;
create table if not exists public.story_metoo (
  id         bigint generated always as identity primary key,
  story_id   bigint not null references public.reactions (id) on delete cascade,
  client     text not null check (char_length(client) between 8 and 64),
  created_at timestamptz not null default now(),
  unique (story_id, client)
);
alter table public.story_metoo enable row level security;
drop policy if exists "story_metoo_insert" on public.story_metoo;
create policy "story_metoo_insert" on public.story_metoo for insert to anon, authenticated with check (true);
create or replace view public.story_metoo_counts with (security_invoker = false) as
  select story_id, count(*)::int as n from public.story_metoo group by story_id;

-- 4) "이게 됐어요" 해결 표시: 글쓴이 본인만. 추가만 가능하고 서버가 본인 확인 후 반영 ------
create table if not exists public.solves (
  id         bigint generated always as identity primary key,
  target     text not null check (target in ('question', 'story')),
  target_id  bigint not null,
  reply_id   bigint not null references public.replies (id) on delete cascade,
  client     text not null check (char_length(client) between 8 and 64),
  created_at timestamptz not null default now(),
  unique (target, target_id)
);
alter table public.solves enable row level security;
drop policy if exists "solves_insert" on public.solves;
create policy "solves_insert" on public.solves for insert to anon, authenticated with check (true);

create or replace function public.solves_apply()
returns trigger language plpgsql security definer set search_path = public as $$
declare owner text; ok boolean;
begin
  select exists(select 1 from public.replies r where r.id = new.reply_id and r.target = new.target and r.target_id = new.target_id) into ok;
  if not ok then raise exception '답글이 그 글에 달린 것이 아닙니다'; end if;
  if new.target = 'question' then
    select client into owner from public.questions where id = new.target_id;
    if owner is null or owner <> new.client then raise exception '질문을 올린 사람만 해결 표시를 할 수 있어요'; end if;
    update public.questions set solved_reply_id = new.reply_id where id = new.target_id;
  else
    select client into owner from public.reactions where id = new.target_id and kind = 'blocked';
    if owner is null or owner <> new.client then raise exception '사연을 올린 사람만 해결 표시를 할 수 있어요'; end if;
    update public.reactions set solved_reply_id = new.reply_id where id = new.target_id;
  end if;
  return new;
end $$;
drop trigger if exists solves_apply on public.solves;
create trigger solves_apply before insert on public.solves
  for each row execute function public.solves_apply();

-- 도구별 "질문 해결 N건": 해결 답글이 추천한 도구 기준
create or replace view public.tool_solved_counts with (security_invoker = true) as
  select r.rec_tool as tool_id, count(*)::int as n
  from public.questions q join public.replies r on r.id = q.solved_reply_id
  where r.rec_tool is not null
  group by r.rec_tool;

-- 5) 신고 대상에 답글·질문 추가 (3회면 자동 숨김) ----------------------------
alter table public.reports drop constraint if exists reports_target_check;
alter table public.reports add constraint reports_target_check check (target in ('review', 'comment', 'reply', 'question'));
create or replace function public.reports_auto_hide()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.reports where target = new.target and target_id = new.target_id;
  if n >= 3 then
    if new.target = 'comment' then update public.comments set hidden = true where id = new.target_id;
    elsif new.target = 'reply' then update public.replies set hidden = true where id = new.target_id;
    elsif new.target = 'question' then update public.questions set hidden = true where id = new.target_id;
    else update public.reviews set hidden = true where id = new.target_id; end if;
  end if;
  return new;
end $$;

-- 6) 메인 "지금 대화 중" 띠: 최근 질문·답글·댓글을 한 줄로 --------------------
create or replace view public.activity_feed with (security_invoker = true) as
  select 'question' as kind, q.id, q.tool_id, q.nick, left(q.body, 80) as body, q.created_at from public.questions q where q.hidden = false
  union all
  select 'reply', r.id, coalesce(r.tool_id, r.rec_tool), r.nick, left(r.body, 80), r.created_at from public.replies r where r.hidden = false
  union all
  select 'comment', c.id, c.tool_id, c.nick, left(c.body, 80), c.created_at from public.comments c where c.hidden = false;

-- 7) 권한 --------------------------------------------------------
grant select, insert on public.questions, public.replies to anon, authenticated;
grant insert on public.story_metoo, public.solves to anon, authenticated;
grant select on public.story_metoo_counts, public.tool_solved_counts, public.activity_feed to anon, authenticated;
-- 끝. "Success. No rows returned" 가 나오면 성공입니다.

-- 8) (추가) 한 줄 평에도 답글 허용 — 상세 창을 글 목록 하나로 합치면서 필요 ----------
alter table public.replies drop constraint if exists replies_target_check;
alter table public.replies add constraint replies_target_check check (target in ('comment', 'story', 'question', 'review'));

-- 7) 답글의 답글(깊이 제한 없음) + 모든 답글에 추천 ------------------------------
alter table public.replies add column if not exists parent_id bigint references public.replies (id) on delete cascade;
alter table public.replies add column if not exists likes integer not null default 0;
create index if not exists replies_parent on public.replies (parent_id);

-- 자식 답글은 부모의 target·target_id·tool_id를 그대로 물려받는다 (클라이언트가 틀려도 서버가 맞춤)
create or replace function public.replies_inherit_parent()
returns trigger language plpgsql security definer set search_path = public as $$
declare p record;
begin
  if new.parent_id is not null then
    select target, target_id, tool_id into p from public.replies where id = new.parent_id and hidden = false;
    if p is null then raise exception '답글을 달 글이 없어요'; end if;
    new.target := p.target; new.target_id := p.target_id; new.tool_id := p.tool_id;
  end if;
  new.likes := 0;
  return new;
end $$;
drop trigger if exists replies_inherit_parent on public.replies;
create trigger replies_inherit_parent before insert on public.replies
  for each row execute function public.replies_inherit_parent();

-- 답글 추천 (브라우저별 답글당 1회). 추천 수는 서버가 세어 replies.likes에 반영
create table if not exists public.reply_likes (
  id         bigint generated always as identity primary key,
  reply_id   bigint not null references public.replies (id) on delete cascade,
  client     text not null check (char_length(client) between 8 and 64),
  created_at timestamptz not null default now(),
  unique (reply_id, client)
);
alter table public.reply_likes enable row level security;
drop policy if exists "reply_likes_insert" on public.reply_likes;
create policy "reply_likes_insert" on public.reply_likes for insert to anon, authenticated with check (true);
grant insert on public.reply_likes to anon, authenticated;

create or replace function public.reply_likes_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.replies set likes = (select count(*) from public.reply_likes where reply_id = new.reply_id) where id = new.reply_id;
  return new;
end $$;
drop trigger if exists reply_likes_count on public.reply_likes;
create trigger reply_likes_count after insert on public.reply_likes
  for each row execute function public.reply_likes_count();

-- 8) 메인 칸별 클릭 집계 (어느 칸이 선호되는지 보고 2주 뒤 순서 재결정) ------------------
create table if not exists public.section_clicks (
  id         bigint generated always as identity primary key,
  section    text not null check (section in ('md', 'gh', 'hot', 'week', 'new')),
  tool_id    text not null check (char_length(tool_id) between 1 and 80),
  client     text not null check (char_length(client) between 8 and 64),
  created_at timestamptz not null default now()
);
create index if not exists section_clicks_time on public.section_clicks (created_at desc);
alter table public.section_clicks enable row level security;
drop policy if exists "section_clicks_insert" on public.section_clicks;
create policy "section_clicks_insert" on public.section_clicks for insert to anon, authenticated with check (true);
grant insert on public.section_clicks to anon, authenticated;
-- 표는 insert만 열고, 집계 뷰만 읽게 (security_invoker = false 라 RLS를 넘어 센다)
create or replace view public.section_clicks_week with (security_invoker = false) as
  select section, count(*)::int as n
  from public.section_clicks
  where created_at > now() - interval '7 days'
  group by section order by n desc;
grant select on public.section_clicks_week to anon, authenticated;
