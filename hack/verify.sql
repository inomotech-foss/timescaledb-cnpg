-- Exercises the TimescaleDB Community (TSL) features this image exists to
-- provide. Anything the Apache 2 edition already covers is not interesting
-- here. Run with ON_ERROR_STOP so any failure aborts.

CREATE EXTENSION timescaledb;

CREATE TABLE metrics (
    time   timestamptz      NOT NULL,
    tag_id integer          NOT NULL,
    value  double precision NOT NULL
);

SELECT create_hypertable('metrics', 'time', chunk_time_interval => INTERVAL '7 days');

-- Hypercore columnstore compression.
ALTER TABLE metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'tag_id'
);

SELECT add_compression_policy('metrics', INTERVAL '7 days');

INSERT INTO metrics
SELECT now() - (s || ' seconds')::interval, 1, s
FROM generate_series(1, 600) AS s;

SELECT compress_chunk(c) FROM show_chunks('metrics') AS c;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.chunks
        WHERE hypertable_name = 'metrics' AND is_compressed
    ) THEN
        RAISE EXCEPTION 'metrics has no compressed chunks';
    END IF;
    IF (SELECT count(*) FROM metrics) IS DISTINCT FROM 600::bigint
       OR (SELECT sum(value) FROM metrics) IS DISTINCT FROM 180300::double precision THEN
        RAISE EXCEPTION 'compressed metrics returned unexpected values';
    END IF;
END $$;

-- Continuous aggregate and its refresh policy.
CREATE MATERIALIZED VIEW metrics_1m
    WITH (timescaledb.continuous) AS
SELECT time_bucket('1 minute', time) AS bucket,
       tag_id,
       avg(value) AS avg_value
FROM metrics
GROUP BY bucket, tag_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('metrics_1m',
    start_offset      => INTERVAL '1 day',
    end_offset        => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute');

CALL refresh_continuous_aggregate('metrics_1m', NULL, NULL);

-- Data retention.
SELECT add_retention_policy('metrics', INTERVAL '365 days');

-- Gap filling.
SELECT time_bucket_gapfill('1 minute', time,
           now() - INTERVAL '10 minutes', now()) AS bucket,
       locf(avg(value)) AS value
FROM metrics
WHERE time > now() - INTERVAL '10 minutes'
GROUP BY bucket
ORDER BY bucket
LIMIT 3;
