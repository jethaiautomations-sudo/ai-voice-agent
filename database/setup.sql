-- =====================================================================
--  AI Voice Customer Service Agent  -  database schema + demo data
--  Safe to re-run: tables use IF NOT EXISTS, demo rows are upserted.
--  Re-run it any time to refresh the demo bookings' dates (they are
--  relative to today, so "tomorrow's booking" is always tomorrow).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- used to rank knowledge-base matches

-- ---------- CRM: one row per customer (keyed by phone number) --------
CREATE TABLE IF NOT EXISTS customers (
    id              SERIAL PRIMARY KEY,
    phone           TEXT UNIQUE NOT NULL,
    name            TEXT,
    email           TEXT,
    total_calls     INT  NOT NULL DEFAULT 0,
    escalations     INT  NOT NULL DEFAULT 0,
    last_call_id    TEXT,
    last_call_reason TEXT,
    last_sentiment  TEXT,
    last_summary    TEXT,
    first_seen      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_contact    TIMESTAMPTZ
);

-- ---------- Business system (demo: hotel reservations) ---------------
CREATE TABLE IF NOT EXISTS bookings (
    booking_number   TEXT PRIMARY KEY,
    guest_first_name TEXT NOT NULL,
    guest_last_name  TEXT NOT NULL,
    guest_email      TEXT,
    guest_phone      TEXT,
    room_type        TEXT NOT NULL,
    rate_plan        TEXT NOT NULL DEFAULT 'flexible',   -- flexible | non_refundable
    status           TEXT NOT NULL DEFAULT 'confirmed',  -- confirmed | cancelled | checked_in | completed
    check_in         DATE NOT NULL,
    check_out        DATE NOT NULL,
    total_amount     NUMERIC(10,2) NOT NULL,
    currency         TEXT NOT NULL DEFAULT 'USD',
    payment_status   TEXT NOT NULL DEFAULT 'paid',
    change_count     INT  NOT NULL DEFAULT 0,
    cancelled_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- Knowledge base (searched with Postgres full-text) --------
CREATE TABLE IF NOT EXISTS knowledge_base (
    id            SERIAL PRIMARY KEY,
    topic         TEXT NOT NULL,
    question      TEXT NOT NULL,
    answer        TEXT NOT NULL,
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(topic,'') || ' ' || coalesce(question,'') || ' ' || coalesce(answer,''))
    ) STORED
);
CREATE INDEX IF NOT EXISTS knowledge_base_fts ON knowledge_base USING GIN (search_vector);
CREATE UNIQUE INDEX IF NOT EXISTS knowledge_base_question_uq ON knowledge_base (question);

-- ---------- Call history ---------------------------------------------
CREATE TABLE IF NOT EXISTS calls (
    call_id               TEXT PRIMARY KEY,
    caller_phone          TEXT,
    customer_name         TEXT,
    booking_number        TEXT,
    status                TEXT NOT NULL DEFAULT 'in_progress',   -- in_progress | completed
    started_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at              TIMESTAMPTZ,
    duration_seconds      INT,
    ended_reason          TEXT,
    call_reason           TEXT,
    primary_intent        TEXT,
    sentiment             TEXT,
    customer_satisfaction INT,
    resolved_by_ai        BOOLEAN,
    escalated             BOOLEAN NOT NULL DEFAULT false,
    ticket_number         TEXT,
    follow_up_required    BOOLEAN,
    follow_up_reason      TEXT,
    summary               TEXT,
    transcript            TEXT,
    recording_url         TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS calls_created_idx ON calls (created_at DESC);

CREATE TABLE IF NOT EXISTS call_turns (
    id         BIGSERIAL PRIMARY KEY,
    call_id    TEXT NOT NULL,
    speaker    TEXT NOT NULL,                 -- customer | agent
    text       TEXT NOT NULL,
    intent     TEXT,
    escalated  BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS call_turns_call_idx ON call_turns (call_id, id);

-- ---------- Human hand-off tickets -----------------------------------
CREATE SEQUENCE IF NOT EXISTS ticket_number_seq START 1001;

CREATE TABLE IF NOT EXISTS support_tickets (
    id               SERIAL PRIMARY KEY,
    ticket_number    TEXT UNIQUE NOT NULL DEFAULT ('TCK-' || nextval('ticket_number_seq')::text),
    call_id          TEXT UNIQUE NOT NULL,         -- one ticket per call
    customer_name    TEXT,
    customer_phone   TEXT,
    booking_number   TEXT,
    category         TEXT,
    priority         TEXT NOT NULL DEFAULT 'normal',   -- low | normal | high | urgent
    status           TEXT NOT NULL DEFAULT 'open',     -- open | in_progress | resolved
    reason           TEXT,
    summary          TEXT,
    requested_action TEXT,
    relevant_info    TEXT,
    suggested_action TEXT,
    transcript       TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
--  DEMO DATA  (Grand Palm Hotel - fictional)
-- =====================================================================

-- Booking rules used by the agent's tools:
--   * can be changed / cancelled only if: status = confirmed, rate_plan = flexible,
--     and check-in is at least 1 day away (tomorrow or later).
INSERT INTO bookings (booking_number, guest_first_name, guest_last_name, guest_email, guest_phone, room_type, rate_plan, status, check_in, check_out, total_amount, payment_status)
VALUES
 ('HB-12345','John',  'Smith',   'john.smith@example.com',  '+15550100001','Deluxe King',   'flexible',       'confirmed', CURRENT_DATE + 1,  CURRENT_DATE + 4,  540.00,'paid'),
 ('HB-20001','Maria', 'Santos',  'maria.santos@example.com','+15550100002','Ocean View Suite','non_refundable','confirmed', CURRENT_DATE + 10, CURRENT_DATE + 12, 780.00,'paid'),
 ('HB-30077','Alex',  'Chen',    'alex.chen@example.com',   '+15550100003','Twin Room',      'flexible',       'confirmed', CURRENT_DATE + 20, CURRENT_DATE + 25, 1125.00,'paid'),
 ('HB-40010','Priya', 'Patel',   'priya.patel@example.com', '+15550100004','Deluxe King',    'flexible',       'confirmed', CURRENT_DATE,      CURRENT_DATE + 2,  360.00,'paid'),
 ('HB-50002','Liam',  'O''Connor', 'liam.oconnor@example.com','+15550100005','Standard Queen', 'flexible',       'cancelled', CURRENT_DATE + 7,  CURRENT_DATE + 9,  260.00,'refunded')
ON CONFLICT (booking_number) DO UPDATE SET
    guest_first_name = EXCLUDED.guest_first_name, guest_last_name = EXCLUDED.guest_last_name,
    guest_email = EXCLUDED.guest_email, guest_phone = EXCLUDED.guest_phone,
    room_type = EXCLUDED.room_type, rate_plan = EXCLUDED.rate_plan, status = EXCLUDED.status,
    check_in = EXCLUDED.check_in, check_out = EXCLUDED.check_out,
    total_amount = EXCLUDED.total_amount, payment_status = EXCLUDED.payment_status,
    change_count = 0, cancelled_at = NULL, updated_at = now();

INSERT INTO knowledge_base (topic, question, answer) VALUES
 ('Check-in',        'What time is check-in?',                 'Check-in starts at 3 PM. Early check-in from 11 AM is subject to availability and is free for members of our loyalty program; otherwise it costs 30 dollars.'),
 ('Check-out',       'What time is check-out?',                'Check-out is at 11 AM. Late check-out until 2 PM is available for 40 dollars, subject to availability. Please ask the front desk on the day.'),
 ('Opening hours',   'What are the front desk opening hours?', 'The front desk is open 24 hours a day, 7 days a week.'),
 ('Opening hours',   'What are the restaurant opening hours?', 'Our restaurant, The Palm Terrace, serves breakfast from 6:30 AM to 10:30 AM, lunch from 12 PM to 3 PM and dinner from 6 PM to 10:30 PM every day.'),
 ('Opening hours',   'What are the spa and pool opening hours?','The pool is open from 7 AM to 10 PM. The spa is open from 9 AM to 9 PM and appointments are recommended.'),
 ('Pricing',         'How much is breakfast?',                 'Breakfast buffet is 25 dollars per adult and 12 dollars per child aged 6 to 12. Children under 6 eat free. It is included in some rate plans, which is shown on the booking.'),
 ('Pricing',         'How much is parking?',                   'Self parking is 20 dollars per night and valet parking is 35 dollars per night. Parking is free for guests who book the Ocean View Suite.'),
 ('Pricing',         'What is the price of a room?',           'Room prices depend on the dates. As a guide, Standard Queen starts from 130 dollars per night, Deluxe King from 180 dollars, Twin Room from 225 dollars and Ocean View Suite from 390 dollars. For an exact quote for specific dates, please check our website or a team member can help.'),
 ('Policy',          'What is the cancellation policy?',       'Flexible rate bookings can be cancelled free of charge up to 24 hours before check-in and are refunded to the original payment method within 5 to 7 business days. Non-refundable bookings cannot be cancelled or refunded.'),
 ('Policy',          'Can I change my booking dates?',         'Flexible rate bookings can be moved to new dates up to 24 hours before check-in, subject to availability. Non-refundable bookings cannot be changed. Changes within 24 hours of check-in need to be handled by our reservations team.'),
 ('Policy',          'Are pets allowed?',                      'Small dogs and cats up to 10 kilograms are welcome in selected rooms for a fee of 30 dollars per stay. Service animals stay free.'),
 ('Policy',          'Is smoking allowed?',                    'All rooms are non-smoking. There is a designated smoking area by the garden entrance. A 250 dollar cleaning fee applies for smoking in rooms.'),
 ('Policy',          'What payment methods do you accept?',    'We accept Visa, Mastercard, American Express and cash. Please never share card numbers by phone with our automated assistant.'),
 ('Services',        'Do you have free wifi?',                 'Yes, high speed wifi is free throughout the hotel for all guests.'),
 ('Services',        'Do you offer an airport shuttle?',       'Yes, we run a shuttle from the airport every hour from 6 AM to 10 PM. It costs 15 dollars per person one way and must be booked at least 12 hours ahead.'),
 ('Services',        'Is there a gym?',                        'The fitness center is open 24 hours for hotel guests and is free of charge.'),
 ('Services',        'Do you have room service?',              'Room service is available from 6 AM to 11 PM. A 5 dollar delivery fee applies.'),
 ('Family',          'Do you allow children? Are there extra beds?','Children are very welcome. Kids under 12 stay free using existing bedding. A rollaway bed or crib can be added for 25 dollars per night, subject to availability.'),
 ('Location',        'Where is the hotel? What is the address?','Grand Palm Hotel is at 100 Ocean Drive, Palm Bay. We are 20 minutes from the airport and a 5 minute walk from the beach.'),
 ('Contact',         'How can I contact reservations?',        'Our reservations team is available by phone from 8 AM to 8 PM daily, or by email at reservations at grandpalm dot example.')
ON CONFLICT (question) DO UPDATE SET topic = EXCLUDED.topic, answer = EXCLUDED.answer;

-- =====================================================================
--  Handy analytics view (the workflow's dashboard uses similar SQL)
-- =====================================================================
CREATE OR REPLACE VIEW v_call_kpis_30d AS
SELECT
    count(*)                                                        AS calls_received,
    count(*) FILTER (WHERE resolved_by_ai)                          AS ai_resolved,
    count(*) FILTER (WHERE escalated)                               AS human_escalated,
    count(*) FILTER (WHERE NOT coalesce(resolved_by_ai,false) AND NOT escalated) AS unresolved,
    round(avg(duration_seconds))                                    AS avg_handle_seconds
FROM calls
WHERE status = 'completed' AND created_at >= now() - interval '30 days';
