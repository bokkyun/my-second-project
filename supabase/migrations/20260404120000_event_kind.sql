-- 일정(schedule) vs 그룹 전체 이벤트(group_event)
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS event_kind text NOT NULL DEFAULT 'schedule';

ALTER TABLE public.events
  DROP CONSTRAINT IF EXISTS events_event_kind_check;

ALTER TABLE public.events
  ADD CONSTRAINT events_event_kind_check
  CHECK (event_kind IN ('schedule', 'group_event'));

COMMENT ON COLUMN public.events.event_kind IS 'schedule: 일반 일정, group_event: 선택 그룹 전체에 공유되는 이벤트';
