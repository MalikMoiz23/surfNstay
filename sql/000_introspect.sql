-- SurfNStay — schema introspection. Run in Supabase SQL Editor, paste the full output back.
-- Read-only. Changes nothing.

-- 1. Columns of every table the app touches
SELECT table_name, ordinal_position AS pos, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'properties','bookings','travellers','hosts','notifications',
    'messages','chats','ratings','reports','admins'
  )
ORDER BY table_name, ordinal_position;

-- 2. Primary keys and foreign keys
SELECT tc.table_name, tc.constraint_type, kcu.column_name,
       ccu.table_name AS references_table, ccu.column_name AS references_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
LEFT JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
WHERE tc.table_schema = 'public'
  AND tc.constraint_type IN ('PRIMARY KEY','FOREIGN KEY','UNIQUE')
ORDER BY tc.table_name, tc.constraint_type;

-- 3. Is RLS currently enabled? (This answers A3 definitively.)
SELECT relname AS table_name, relrowsecurity AS rls_enabled, relforcerowsecurity AS rls_forced
FROM pg_class
WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r','v')
ORDER BY relname;

-- 4. Existing policies, if any
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 5. Distinct booking statuses currently in use
SELECT status, count(*) FROM bookings GROUP BY status ORDER BY 2 DESC;

-- 6. Pre-flight for the overlap constraint: any ALREADY-overlapping confirmed bookings?
--    These must be resolved before the EXCLUDE constraint can be created.
SELECT a.id AS booking_a, b.id AS booking_b, a.property_id,
       a.start_date, a.end_date, b.start_date, b.end_date
FROM bookings a
JOIN bookings b
  ON a.property_id = b.property_id
 AND a.id < b.id
 AND daterange(a.start_date, a.end_date, '[]') && daterange(b.start_date, b.end_date, '[]')
WHERE a.status IN ('confirmed','completed')
  AND b.status IN ('confirmed','completed');

-- 7. Does the admin_report_view exist, and what is it?
SELECT viewname, definition FROM pg_views WHERE schemaname = 'public';
