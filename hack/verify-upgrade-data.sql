-- Run with both old and updated extension catalogs, in separate sessions from ALTER EXTENSION.
DO $$
DECLARE
    counter_delta double precision;
    persisted_delta double precision;
BEGIN
    IF (SELECT count(*) FROM metrics) IS DISTINCT FROM 600::bigint
       OR (SELECT sum(value) FROM metrics) IS DISTINCT FROM 180300::double precision THEN
        RAISE EXCEPTION 'hypertable data changed across upgrade';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM metrics_1m) THEN
        RAISE EXCEPTION 'continuous aggregate is empty after restart';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.chunks
        WHERE hypertable_name = 'metrics' AND is_compressed
    ) THEN
        RAISE EXCEPTION 'compressed chunk was lost across upgrade';
    END IF;

    SELECT delta(counter_agg(ts, km)) INTO counter_delta FROM odometer;
    SELECT delta(summary) INTO persisted_delta FROM upgrade_counter;
    IF counter_delta IS DISTINCT FROM 35::double precision
       OR persisted_delta IS DISTINCT FROM 35::double precision THEN
        RAISE EXCEPTION 'toolkit counter delta changed: computed %, persisted %',
            counter_delta, persisted_delta;
    END IF;
END $$;
