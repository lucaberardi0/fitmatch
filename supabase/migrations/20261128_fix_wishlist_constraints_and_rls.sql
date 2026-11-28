-- Run this migration in Supabase SQL Editor (or via `supabase db push`)
-- to remove the legacy global UNIQUE(canonical_name) multi-user blocker,
-- deduplicate legacy collection rows, and tighten RLS on wishlists & collections.

BEGIN;

-- 1. Replace broken global UNIQUE(canonical_name) with user-scoped uniqueness
ALTER TABLE public.wishlists DROP CONSTRAINT IF EXISTS wishlists_canonical_name_key;

DELETE FROM public.wishlists w
USING (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id, lower(trim(canonical_name))
             ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id
           ) AS rn
    FROM public.wishlists
    WHERE user_id IS NOT NULL
  ) ranked
  WHERE rn > 1
) dup
WHERE w.id = dup.id;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wishlists_user_canonical_unique'
      AND conrelid = 'public.wishlists'::regclass
  ) THEN
    ALTER TABLE public.wishlists
      ADD CONSTRAINT wishlists_user_canonical_unique UNIQUE (user_id, canonical_name);
  END IF;
END $$;

-- 2. Clean duplicate & reserved collections and add user-scoped uniqueness
DELETE FROM public.collections
WHERE trim(COALESCE(name, '')) = '' OR lower(trim(name)) = 'tutti';

DELETE FROM public.collections c
USING (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY user_id, lower(trim(name))
             ORDER BY created_at ASC NULLS LAST, id
           ) AS rn
    FROM public.collections
    WHERE user_id IS NOT NULL
  ) ranked
  WHERE rn > 1
) dup
WHERE c.id = dup.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_collections_user_name_lower
  ON public.collections (user_id, lower(trim(name)))
  WHERE user_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'collections_user_name_unique'
      AND conrelid = 'public.collections'::regclass
  ) THEN
    ALTER TABLE public.collections
      ADD CONSTRAINT collections_user_name_unique UNIQUE (user_id, name);
  END IF;
END $$;

-- 3. Tighten RLS on wishlists & collections strictly to auth.uid() = user_id
DROP POLICY IF EXISTS "User access wishlists" ON public.wishlists;
CREATE POLICY "User access wishlists"
  ON public.wishlists
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "User access collections" ON public.collections;
CREATE POLICY "User access collections"
  ON public.collections
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

COMMIT;
