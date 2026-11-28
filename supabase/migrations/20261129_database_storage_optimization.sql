-- ============================================================================
-- FitMatch: Database Storage Optimization & Future-Proofing
-- Target: Reclaim ~150-200MB to drop DB size comfortably below 500MB Free quota
-- ============================================================================

-- 1. Point fallback RPC get_home_showcases_fast to v2 so v1 view can be safely dropped
CREATE OR REPLACE FUNCTION public.get_home_showcases_fast()
RETURNS TABLE(
    id text,
    product_id text,
    store_id text,
    store_name text,
    raw_title text,
    current_price numeric,
    original_price numeric,
    discount_pct numeric,
    product_url text,
    image_url text,
    available_sizes jsonb,
    shipping_cost numeric,
    free_shipping_threshold numeric,
    courier text,
    store_rating numeric,
    store_review_count integer,
    store_formatted_review_count text,
    store_card_theme text,
    store_accent_color text,
    store_logo_url text,
    store_total_offers integer,
    store_avg_discount numeric,
    rn bigint
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
    SELECT
        m.id,
        m.product_id,
        m.store_id,
        m.store_name,
        m.raw_title,
        so.current_price,
        so.original_price,
        so.discount_pct,
        so.product_url,
        so.image_url,
        so.available_sizes,
        so.shipping_cost,
        so.free_shipping_threshold,
        so.courier,
        m.store_rating,
        m.store_review_count,
        m.store_formatted_review_count,
        m.store_card_theme,
        m.store_accent_color,
        m.store_logo_url,
        m.store_total_offers,
        m.store_avg_discount,
        m.rn
    FROM public.mv_home_showcases_v2 m
    JOIN public.store_offers so ON so.id = m.id
    WHERE so.in_stock IS DISTINCT FROM false
      AND so.current_price > 0
    ORDER BY m.rn ASC, m.store_id ASC;
$function$;

-- 2. Unschedule obsolete cron jobs refreshing dead v1 views
DO $$
BEGIN
    PERFORM cron.unschedule('refresh_mv_deals_catalog');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    PERFORM cron.unschedule('refresh_mv_home_showcases');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 3. Drop obsolete materialized views and their dependent objects (~31 MB saved)
DROP MATERIALIZED VIEW IF EXISTS public.mv_deals_catalog CASCADE;
DROP MATERIALIZED VIEW IF EXISTS public.mv_home_showcases CASCADE;

-- 4. Drop 100% unused / duplicate heavy indexes (~75 MB saved)
-- 4a. 23MB GIN trigram index on store_offers.raw_title (search uses products.canonical_name)
DROP INDEX IF EXISTS public.idx_offers_raw_title_trgm;

-- 4b. 14MB GIN trigram index on mv_store_catalog_v2 (0 scans recorded)
DROP INDEX IF EXISTS public.idx_mv_store_catalog_v2_search_trgm;

-- 4c. 9.2MB unused btree on products (0 scans recorded)
DROP INDEX IF EXISTS public.idx_products_cat_brand_cover;

-- 4d. 9MB unused btree on store_offers (0 scans recorded)
DROP INDEX IF EXISTS public.idx_store_offers_health_cover;

-- 4e. 5.4MB redundant GIN trigram on products where brand is null (idx_products_name_trgm already covers all)
DROP INDEX IF EXISTS public.idx_products_null_brand_name_trgm;

-- 4f. Unused indexes on materialized views (0 scans recorded)
DROP INDEX IF EXISTS public.idx_mv_store_catalog_v2_store_disc;
DROP INDEX IF EXISTS public.idx_mv_store_catalog_v2_store_score;
DROP INDEX IF EXISTS public.idx_mv_deals_catalog_v2_id;

-- 4g. Redundant single-column btrees on products (covered by primary key or composite indexes)
DROP INDEX IF EXISTS public.idx_products_cat_brand_lower;
DROP INDEX IF EXISTS public.idx_products_brand_lower;
DROP INDEX IF EXISTS public.idx_products_gender;
DROP INDEX IF EXISTS public.idx_products_brand;
DROP INDEX IF EXISTS public.idx_products_embedding_null_cat;

-- 5. Future-proofing: Adjust heavy materialized view refresh frequencies to avoid WAL bloat
-- mv_store_catalog_v2 is 59MB; refreshing every 15 mins caused continuous churn. Set to every 2 hours.
SELECT cron.alter_job(job_id := 11, schedule := '15 */2 * * *');

-- 6. Future-proofing maintenance procedure: cleans old logs and prevents bloat accumulation
CREATE OR REPLACE FUNCTION public.maintain_database_storage()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cron_deleted int := 0;
    v_crawl_deleted int := 0;
    v_sync_deleted int := 0;
BEGIN
    -- Purge cron run history older than 3 days
    DELETE FROM cron.job_run_details
    WHERE start_time < (NOW() - INTERVAL '3 days');
    GET DIAGNOSTICS v_cron_deleted = ROW_COUNT;

    -- Purge crawl logs older than 7 days
    DELETE FROM public.crawl_logs
    WHERE crawled_at < (NOW() - INTERVAL '7 days');
    GET DIAGNOSTICS v_crawl_deleted = ROW_COUNT;

    -- Purge completed sync sessions older than 14 days
    DELETE FROM public.sync_sessions
    WHERE started_at < (NOW() - INTERVAL '14 days')
      AND status IN ('completed', 'failed');
    GET DIAGNOSTICS v_sync_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'cron_logs_purged', v_cron_deleted,
        'crawl_logs_purged', v_crawl_deleted,
        'sync_sessions_purged', v_sync_deleted,
        'maintained_at', NOW()
    );
END;
$$;

-- Schedule daily maintenance at 03:15 UTC
DO $$
BEGIN
    PERFORM cron.unschedule('daily-db-storage-maintenance');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
    'daily-db-storage-maintenance',
    '15 3 * * *',
    'SELECT public.maintain_database_storage();'
);

-- Execute immediate maintenance cleanup
SELECT public.maintain_database_storage();
