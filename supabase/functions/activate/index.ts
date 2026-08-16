// Supabase Edge Function：设备注册 + 激活码验证。
//
// 部署：Supabase Dashboard → Edge Functions → 新建函数 `activate`，粘贴本文件；
//       或 `supabase functions deploy activate`。
// 端点：
//   POST /functions/v1/device    {fingerprint}
//   POST /functions/v1/activate  {code, fingerprint}
//
// 安全：函数内部使用 service_role 操作数据库；客户端只传 anon key 调用函数。

import { createClient } from 'npm:@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const TRIAL_HOURS = 24;

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const path = url.pathname.split('/').filter(Boolean).pop() ?? '';
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  let body: any = {};
  try { body = await req.json(); } catch (_) {}

  try {
    if (path === 'device') {
      return json(cors, await handleDevice(body.fingerprint));
    }
    if (path === 'activate') {
      return json(cors, await handleActivate(body.code, body.fingerprint));
    }
    return json(cors, { error: 'not found' }, 404);
  } catch (e: any) {
    return json(cors, { error: e.message ?? 'internal error' }, 500);
  }
});

function json(headers: Record<string, string>, data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

/// 注册/查询设备：不存在则创建（试用开始）；存在则返回原状态（重装/清数据后恢复）。
async function handleDevice(fingerprint?: string) {
  if (!fingerprint) return { error: 'missing fingerprint' };
  const { data: existing } = await supabase
    .from('devices')
    .select('trial_started_at, activated_until')
    .eq('fingerprint', fingerprint)
    .maybeSingle();

  if (existing) {
    return {
      trialStartedAt: existing.trial_started_at,
      activatedUntil: existing.activated_until,
    };
  }
  const now = new Date().toISOString();
  await supabase.from('devices').insert({
    fingerprint,
    trial_started_at: now,
  });
  return { trialStartedAt: now, activatedUntil: null };
}

/// 激活：验证码 → 标记使用 → 设备续期（取 max(现有到期, 当前) + 时长）。
async function handleActivate(code?: string, fingerprint?: string) {
  if (!code || !fingerprint) return { ok: false, message: '参数不完整' };
  const c = String(code).trim().toUpperCase();

  // 查码（行级锁，防并发超用）
  const { data: codeRow } = await supabase
    .from('codes')
    .select('code, duration_days, max_uses, used_count')
    .eq('code', c)
    .maybeSingle();
  if (!codeRow) return { ok: false, message: '激活码不存在' };
  if (codeRow.used_count >= codeRow.max_uses) {
    return { ok: false, message: '激活码已使用或已达使用上限' };
  }

  // 标记使用（乐观并发：update where used_count < max_uses）
  const { data: updated } = await supabase
    .from('codes')
    .update({ used_count: codeRow.used_count + 1 })
    .eq('code', c)
    .lt('used_count', codeRow.max_uses)
    .select('used_count');
  if (!updated || updated.length === 0) {
    return { ok: false, message: '激活码已使用或已达使用上限' };
  }

  // 设备续期
  const { data: dev } = await supabase
    .from('devices')
    .select('trial_started_at, activated_until')
    .eq('fingerprint', fingerprint)
    .maybeSingle();
  const base = dev?.activated_until && new Date(dev.activated_until) > new Date()
    ? new Date(dev.activated_until)
    : new Date();
  const activatedUntil = new Date(base.getTime() + codeRow.duration_days * 86400_000);
  await supabase.from('devices').upsert({
    fingerprint,
    trial_started_at: dev?.trial_started_at ?? new Date().toISOString(),
    activated_until: activatedUntil.toISOString(),
  });

  return {
    ok: true,
    durationDays: codeRow.duration_days,
    activatedUntil: activatedUntil.toISOString(),
  };
}
