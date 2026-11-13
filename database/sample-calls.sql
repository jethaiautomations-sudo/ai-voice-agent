-- Sample completed calls so the dashboard has data to show right away.
-- Safe to re-run: it removes its own earlier sample rows (call_id starting with 'sample-') first.
--   docker compose exec -T postgres psql -U voice -d voice_agent < sample-calls.sql
-- To remove the samples later:   DELETE FROM calls WHERE call_id LIKE 'sample-%';

DELETE FROM calls WHERE call_id LIKE 'sample-%';

INSERT INTO calls
  (call_id, caller_phone, customer_name, booking_number, status, started_at, ended_at, duration_seconds,
   ended_reason, call_reason, primary_intent, sentiment, customer_satisfaction,
   resolved_by_ai, escalated, follow_up_required, summary)
SELECT
  'sample-' || lpad(g::text, 3, '0'),
  '+1555010' || lpad((g % 40)::text, 4, '0'),
  (ARRAY['John Smith','Maria Santos','Alex Chen','Priya Patel','Liam O''Connor','Sam Lee'])[1 + g % 6],
  'HB-' || (10000 + g * 37),
  'completed',
  now() - (g * interval '7 hours' + (g % 5) * interval '13 minutes'),
  now() - (g * interval '7 hours') + (60 + (g * 23) % 240) * interval '1 second',
  60 + (g * 23) % 240,
  'customer-ended-call',
  -- call reason + intent
  (ARRAY['Asked about check-in time','Change booking date','Cancel a booking','Parking and amenities question',
         'Billing dispute','Airport transfer question','Room upgrade request'])[1 + g % 7],
  (ARRAY['faq','change_booking','cancellation','faq','billing','faq','upsell'])[1 + g % 7],
  -- sentiment
  CASE WHEN g % 7 = 4 THEN 'negative' WHEN g % 3 = 0 THEN 'neutral' ELSE 'positive' END,
  CASE WHEN g % 7 = 4 THEN 2 WHEN g % 3 = 0 THEN 4 ELSE 5 END,
  -- billing disputes are escalated, everything else is resolved by the AI except a few unresolved
  (g % 7 <> 4 AND g % 11 <> 0),
  (g % 7 = 4),
  (g % 7 = 4 OR g % 11 = 0),
  'Sample call for dashboard demo.'
FROM generate_series(1, 24) AS g;

SELECT count(*) AS sample_calls_added FROM calls WHERE call_id LIKE 'sample-%';
