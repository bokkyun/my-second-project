-- 매수 시그널 실시간 반영: signals 테이블 upsert 시 앱이 즉시 갱신되도록 publication 에 포함
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'signals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.signals;
  END IF;
END $$;
