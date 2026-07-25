-- Exercises the TimescaleDB Toolkit hyperfunctions. Each check asserts a computed
-- value, so a toolkit that loads but miscomputes still fails. Run with
-- ON_ERROR_STOP.

CREATE EXTENSION timescaledb_toolkit;

-- counter_agg: a monotonic counter that resets, as an odometer does. Naive
-- last-minus-first goes negative across the reset.
CREATE TABLE odometer (
    ts timestamptz      NOT NULL,
    km double precision NOT NULL
);

INSERT INTO odometer VALUES
    ('2026-01-01 00:00:00Z', 100),
    ('2026-01-01 00:01:00Z', 110),
    ('2026-01-01 00:02:00Z', 120),
    ('2026-01-01 00:03:00Z',   5),  -- counter reset
    ('2026-01-01 00:04:00Z',  15);

DO $$
DECLARE
    resets bigint;
    travelled double precision;
    naive double precision;
BEGIN
    SELECT num_resets(counter_agg(ts, km)), delta(counter_agg(ts, km))
      INTO resets, travelled
      FROM odometer;

    -- What last-minus-first would have returned.
    SELECT (SELECT km FROM odometer ORDER BY ts DESC LIMIT 1)
         - (SELECT km FROM odometer ORDER BY ts      LIMIT 1)
      INTO naive;

    IF resets <> 1 THEN
        RAISE EXCEPTION 'counter_agg detected % resets, expected 1', resets;
    END IF;
    IF naive >= 0 THEN
        RAISE EXCEPTION 'fixture is wrong: naive last-first is %, expected negative', naive;
    END IF;
    -- 20 accumulated before the reset (100 -> 120), then 15 after it (0 -> 15).
    IF travelled IS NULL OR abs(travelled - 35) > 0.001 THEN
        RAISE EXCEPTION 'counter_agg delta is %, expected 35', travelled;
    END IF;

    RAISE NOTICE 'counter_agg: resets=%, delta=% (naive last-first would be %)',
        resets, travelled, naive;
END $$;

-- state_agg: time spent in each state, e.g. ignition on/off to idle duration.
CREATE TABLE ignition (
    ts    timestamptz NOT NULL,
    state text        NOT NULL
);

-- on 00:00-00:01 (60s), off 00:01-00:03, on 00:03-00:04 (60s), off trailing.
INSERT INTO ignition VALUES
    ('2026-01-01 00:00:00Z', 'on'),
    ('2026-01-01 00:01:00Z', 'off'),
    ('2026-01-01 00:03:00Z', 'on'),
    ('2026-01-01 00:04:00Z', 'off');

DO $$
DECLARE
    on_time interval;
BEGIN
    SELECT duration_in(state_agg(ts, state), 'on') INTO on_time FROM ignition;

    IF on_time <> INTERVAL '120 seconds' THEN
        RAISE EXCEPTION 'state_agg duration_in(on) is %, expected 120 seconds', on_time;
    END IF;

    RAISE NOTICE 'state_agg: duration_in(on)=%', on_time;
END $$;

-- time_weight + integral: trapezoidal integration of a rate over time.
CREATE TABLE fuel_rate (
    ts               timestamptz      NOT NULL,
    litres_per_hour  double precision NOT NULL
);

-- A constant 2 l/h across 60 seconds integrates to 120 when the unit is seconds.
INSERT INTO fuel_rate VALUES
    ('2026-01-01 00:00:00Z', 2),
    ('2026-01-01 00:01:00Z', 2);

DO $$
DECLARE
    area double precision;
BEGIN
    SELECT integral(time_weight('Linear', ts, litres_per_hour))
      INTO area
      FROM fuel_rate;

    IF area IS NULL OR abs(area - 120) > 0.001 THEN
        RAISE EXCEPTION 'integral is %, expected 120', area;
    END IF;

    RAISE NOTICE 'time_weight: integral=%', area;
END $$;
