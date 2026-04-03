-- Supabase SQL 에디터에서 실행하거나 `supabase db push`로 적용하세요.

-- FCM 기기 토큰 (그룹 일정 푸시용)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fcm_token text;

COMMENT ON COLUMN public.profiles.fcm_token IS 'Firebase Cloud Messaging 토큰 (선택)';

-- 그룹별: 타인이 등록한 일정 푸시 수신 동의
ALTER TABLE public.group_members
  ADD COLUMN IF NOT EXISTS notify_group_events boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.group_members.notify_group_events IS '그룹원이 일정 등록 시 푸시 알림 수신 여부';
