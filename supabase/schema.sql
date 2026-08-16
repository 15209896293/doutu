-- 豆图试用版 · Supabase 初始化 SQL
-- 在 Supabase 项目 → SQL Editor 中执行本文件。

-- 设备表：试用与激活状态（按设备指纹）
create table if not exists public.devices (
  fingerprint        text primary key,
  trial_started_at   timestamptz not null default now(),
  activated_until    timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- 激活码表：一次性/限量
create table if not exists public.codes (
  code          text primary key,
  duration_days int not null,
  max_uses      int not null default 1,
  used_count    int not null default 0,
  note          text,
  created_at    timestamptz not null default now()
);

-- RLS：客户端一律禁止直读（防泄码），只允许 Edge Function（service_role）读写
alter table public.devices enable row level security;
alter table public.codes enable row level security;
create policy "service_role only" on public.devices for all using (auth.role() = 'service_role');
create policy "service_role only" on public.codes for all using (auth.role() = 'service_role');
revoke all on public.devices from anon, authenticated;
revoke all on public.codes from anon, authenticated;
grant all on public.devices to service_role;
grant all on public.codes to service_role;

-- 自动更新 updated_at
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;
drop trigger if exists devices_touch on public.devices;
create trigger devices_touch before update on public.devices
  for each row execute function public.touch_updated_at();

-- ============================================================
-- 测试码（示例；正式请用 tools/gen_trial_codes.dart 生成随机码再执行）
-- ============================================================
-- 说明：max_uses=1 表示一次性（用后即废，防传播）；测试期可改大。
insert into public.codes (code, duration_days, max_uses, note) values
  ('DOU7D-TEST-0001',   7,    1, '测试：7 天'),
  ('DOU30D-TEST-0001',  30,   1, '测试：30 天'),
  ('DOU90D-TEST-0001',  90,   1, '测试：90 天'),
  ('DOUPERM-TEST-0001', 3650, 1, '测试：永久')
on conflict (code) do nothing;
