-- 캘린더 실시간 동기화: `events` / `event_visibility` 변경을 Realtime으로 브로드캐스트하려면
-- publication 에 포함되어야 합니다. (이미 포함된 환경에서는 IF 블록이 건너뜁니다)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'events'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'event_visibility'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.event_visibility;
  END IF;
END $$;
