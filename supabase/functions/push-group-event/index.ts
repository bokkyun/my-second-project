/**
 * Database Webhook (event_visibility INSERT) 용 Edge Function.
 *
 * FCM HTTP v1 (레거시 서버 키 API는 신규 프로젝트에서 비활성화됨)
 *
 * 시크릿:
 *   FCM_SERVICE_ACCOUNT_JSON — Firebase 서비스 계정 JSON 전체(한 줄로 minify 권장)
 *   Deno.env: SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL
 *
 * 서비스 계정 키 발급:
 *   Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성
 *   (또는 GCP IAM에서 동일 프로젝트의 서비스 계정 키 JSON)
 *
 * 배포: `supabase functions deploy push-group-event --no-verify-jwt`
 * Webhook: table event_visibility, INSERT → 이 함수 URL
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
import { JWT } from "npm:google-auth-library@9.14.2";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!saJson) {
    return json({ error: "FCM_SERVICE_ACCOUNT_JSON not set" }, 500);
  }

  let cred: {
    project_id: string;
    client_email: string;
    private_key: string;
  };
  try {
    cred = JSON.parse(saJson);
  } catch {
    return json({ error: "FCM_SERVICE_ACCOUNT_JSON is not valid JSON" }, 500);
  }

  if (!cred.project_id || !cred.client_email || !cred.private_key) {
    return json({ error: "service account JSON missing project_id/client_email/private_key" }, 500);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  const rec = (body.record ?? body) as { event_id?: string; group_id?: string };
  const eventId = rec.event_id;
  const groupId = rec.group_id;

  if (!eventId || !groupId) {
    return json({ error: "need event_id and group_id" }, 400);
  }

  const { data: eventRow, error: evErr } = await supabase
    .from("events")
    .select("id, title, starts_at, is_all_day, creator_id, event_kind")
    .eq("id", eventId)
    .maybeSingle();

  if (evErr || !eventRow) {
    return json({ error: "event not found", detail: evErr?.message }, 404);
  }

  const { data: groupRow } = await supabase
    .from("groups")
    .select("name")
    .eq("id", groupId)
    .maybeSingle();

  const { data: creatorProf } = await supabase
    .from("profiles")
    .select("nickname")
    .eq("id", eventRow.creator_id as string)
    .maybeSingle();

  const nickname = (creatorProf?.nickname as string | undefined) ?? "멤버";
  const groupName = (groupRow?.name as string | undefined) ?? "그룹";

  const startsAt = new Date(eventRow.starts_at as string);
  const timeLabel = eventRow.is_all_day
    ? "하루 종일"
    : `${String(startsAt.getHours()).padStart(2, "0")}:${
      String(startsAt.getMinutes()).padStart(2, "0")
    }`;

  const kind = eventRow.event_kind as string | undefined;
  const prefix = kind === "group_event" ? "그룹 이벤트" : "새 일정";
  const notificationTitle = `${prefix} · ${groupName}`;
  const notificationBody =
    `${nickname}: ${eventRow.title as string} (${timeLabel})`;

  const { data: members, error: memErr } = await supabase
    .from("group_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("notify_group_events", true);

  if (memErr) {
    return json({ error: memErr.message }, 500);
  }

  const creatorId = eventRow.creator_id as string;
  const userIds = (members ?? [])
    .map((m) => m.user_id as string)
    .filter((id) => id !== creatorId);

  if (userIds.length === 0) {
    return json({ ok: true, sent: 0, message: "no recipients" });
  }

  const { data: profiles } = await supabase
    .from("profiles")
    .select("fcm_token")
    .in("id", userIds)
    .not("fcm_token", "is", null);

  const tokens = (profiles ?? [])
    .map((p) => p.fcm_token as string)
    .filter((t) => t && t.length > 0);

  if (tokens.length === 0) {
    return json({ ok: true, sent: 0, message: "no fcm tokens" });
  }

  const accessToken = await getFcmAccessToken(cred);
  const fcmUrl =
    `https://fcm.googleapis.com/v1/projects/${cred.project_id}/messages:send`;

  let sent = 0;
  const concurrency = 15;
  for (let i = 0; i < tokens.length; i += concurrency) {
    const batch = tokens.slice(i, i + concurrency);
    const results = await Promise.all(
      batch.map((token) =>
        sendFcmV1(fcmUrl, accessToken, token, notificationTitle, notificationBody, {
          type: "group_event",
          event_id: String(eventId),
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        })
      ),
    );
    for (const ok of results) {
      if (ok) sent++;
    }
  }

  return json({ ok: true, sent, targets: tokens.length });
});

async function getFcmAccessToken(cred: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const client = new JWT({
    email: cred.client_email,
    key: cred.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const tok = await client.getAccessToken();
  if (!tok.token) {
    throw new Error("failed to get Google access token for FCM");
  }
  return tok.token;
}

async function sendFcmV1(
  url: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
      },
    }),
  });

  if (!res.ok) {
    const t = await res.text();
    console.error("FCM v1 error", res.status, t);
    return false;
  }
  return true;
}

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

function json(obj: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}
