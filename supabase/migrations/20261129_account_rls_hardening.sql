-- Run this migration in Supabase SQL Editor (after deploying the updated iOS app
-- that sends user JWTs on all user-table requests) to deduplicate legacy rows,
-- enforce user-scoped uniqueness, and lock down RLS strictly to auth.uid() = user_id.

BEGIN;

-- 1. Deduplicate user_preferences by user_id and enforce user-scoped uniqueness
DELETE FROM public.user_preferences up
USING (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id
             ORDER BY updated_at DESC NULLS LAST, id DESC
           ) AS rn
    FROM public.user_preferences
    WHERE user_id IS NOT NULL
  ) ranked
  WHERE rn > 1
) dup
WHERE up.id = dup.id;

ALTER TABLE public.user_preferences
  DROP CONSTRAINT IF EXISTS user_preferences_device_id_key;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_preferences_user_id_unique'
      AND conrelid = 'public.user_preferences'::regclass
  ) THEN
    ALTER TABLE public.user_preferences
      ADD CONSTRAINT user_preferences_user_id_unique UNIQUE (user_id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_preferences_device_unowned
  ON public.user_preferences (device_id)
  WHERE user_id IS NULL AND device_id IS NOT NULL;

-- 2. Deduplicate followed_stores & hidden_stores by (user_id, store_id)
UPDATE public.followed_stores
SET store_id = lower(trim(store_id))
WHERE store_id IS DISTINCT FROM lower(trim(store_id));

DELETE FROM public.followed_stores fs
USING (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id, store_id
             ORDER BY created_at DESC NULLS LAST, id DESC
           ) AS rn
    FROM public.followed_stores
    WHERE user_id IS NOT NULL
  ) ranked
  WHERE rn > 1
) dup
WHERE fs.id = dup.id;

ALTER TABLE public.followed_stores
  DROP CONSTRAINT IF EXISTS followed_stores_device_store_uniq;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'followed_stores_user_store_unique'
      AND conrelid = 'public.followed_stores'::regclass
  ) THEN
    ALTER TABLE public.followed_stores
      ADD CONSTRAINT followed_stores_user_store_unique UNIQUE (user_id, store_id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_followed_stores_device_unowned
  ON public.followed_stores (device_id, store_id)
  WHERE user_id IS NULL AND device_id IS NOT NULL;

UPDATE public.hidden_stores
SET store_id = lower(trim(store_id))
WHERE store_id IS DISTINCT FROM lower(trim(store_id));

DELETE FROM public.hidden_stores hs
USING (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id, store_id
             ORDER BY created_at DESC NULLS LAST, id DESC
           ) AS rn
    FROM public.hidden_stores
    WHERE user_id IS NOT NULL
  ) ranked
  WHERE rn > 1
) dup
WHERE hs.id = dup.id;

ALTER TABLE public.hidden_stores
  DROP CONSTRAINT IF EXISTS hidden_stores_device_store_uniq;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'hidden_stores_user_store_unique'
      AND conrelid = 'public.hidden_stores'::regclass
  ) THEN
    ALTER TABLE public.hidden_stores
      ADD CONSTRAINT hidden_stores_user_store_unique UNIQUE (user_id, store_id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_hidden_stores_device_unowned
  ON public.hidden_stores (device_id, store_id)
  WHERE user_id IS NULL AND device_id IS NOT NULL;

-- 3. Strict auth.uid()-scoped RLS on all user-owned tables
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public all user_preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "User access user_preferences" ON public.user_preferences;
CREATE POLICY "User access user_preferences"
  ON public.user_preferences FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.followed_stores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public all followed_stores" ON public.followed_stores;
DROP POLICY IF EXISTS "User access followed_stores" ON public.followed_stores;
CREATE POLICY "User access followed_stores"
  ON public.followed_stores FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.hidden_stores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public all hidden_stores" ON public.hidden_stores;
DROP POLICY IF EXISTS "User access hidden_stores" ON public.hidden_stores;
CREATE POLICY "User access hidden_stores"
  ON public.hidden_stores FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.recent_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public all recent_activity" ON public.recent_activity;
DROP POLICY IF EXISTS "User access recent_activity" ON public.recent_activity;
CREATE POLICY "User access recent_activity"
  ON public.recent_activity FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read/write device_tokens" ON public.device_tokens;
DROP POLICY IF EXISTS "User access device_tokens" ON public.device_tokens;
CREATE POLICY "User access device_tokens"
  ON public.device_tokens FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read/write notifications" ON public.notifications;
DROP POLICY IF EXISTS "User access notifications" ON public.notifications;
CREATE POLICY "User access notifications"
  ON public.notifications FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.chat_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public all chat_sessions" ON public.chat_sessions;
DROP POLICY IF EXISTS "User access chat_sessions" ON public.chat_sessions;
CREATE POLICY "User access chat_sessions"
  ON public.chat_sessions FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public all chat_messages" ON public.chat_messages;
DROP POLICY IF EXISTS "User access chat_messages" ON public.chat_messages;
CREATE POLICY "User access chat_messages"
  ON public.chat_messages FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.chat_sessions cs WHERE cs.id = session_id AND cs.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.chat_sessions cs WHERE cs.id = session_id AND cs.user_id = auth.uid()));

ALTER TABLE public.store_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public insert store_reports" ON public.store_reports;
DROP POLICY IF EXISTS "Allow public read store_reports" ON public.store_reports;
DROP POLICY IF EXISTS "User access store_reports" ON public.store_reports;
CREATE POLICY "User access store_reports"
  ON public.store_reports FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.search_feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public delete search_feedback" ON public.search_feedback;
DROP POLICY IF EXISTS "Allow public insert search_feedback" ON public.search_feedback;
DROP POLICY IF EXISTS "Allow public read search_feedback" ON public.search_feedback;
DROP POLICY IF EXISTS "User access search_feedback" ON public.search_feedback;
CREATE POLICY "User access search_feedback"
  ON public.search_feedback FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.store_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow delete to store_reviews" ON public.store_reviews;
DROP POLICY IF EXISTS "Allow update to store_reviews" ON public.store_reviews;
DROP POLICY IF EXISTS "Allow public insert to store_reviews" ON public.store_reviews;
DROP POLICY IF EXISTS "Allow public read access to store_reviews" ON public.store_reviews;
DROP POLICY IF EXISTS "Public read store_reviews" ON public.store_reviews;
DROP POLICY IF EXISTS "Authenticated insert store_reviews" ON public.store_reviews;
DROP POLICY IF EXISTS "Owner update store_reviews" ON public.store_reviews;
DROP POLICY IF EXISTS "Owner delete store_reviews" ON public.store_reviews;

CREATE POLICY "Public read store_reviews"
  ON public.store_reviews FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "Authenticated insert store_reviews"
  ON public.store_reviews FOR INSERT TO authenticated
  WITH CHECK (user_id IS NULL OR auth.uid() = user_id);

CREATE POLICY "Owner update store_reviews"
  ON public.store_reviews FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Owner delete store_reviews"
  ON public.store_reviews FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

COMMIT;
