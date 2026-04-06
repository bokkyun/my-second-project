-- 메모/설명 필드 (앱의 EventService·CalendarEvent 모델과 일치)
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS description text;

COMMENT ON COLUMN public.events.description IS '일정 메모(선택)';
