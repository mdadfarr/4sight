-- 4sight near-miss database on Tiger Cloud (TimescaleDB + PostGIS), per docs/DATA_PIPELINE.md.
-- Idempotent: safe to run again on a live service.
--   psql "$DATABASE_URL" -f server/schema.sql

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Streets riders are matched to: OpenStreetMap, or the City Cycling Network when loaded
-- (tools/load_segments.py). ward is null until the City file is in.
CREATE TABLE IF NOT EXISTS segments (
    id        text PRIMARY KEY,
    street    text,
    lane_type text NOT NULL CHECK (lane_type IN ('protected', 'painted', 'shared', 'none')),
    ward      int,
    ward_name text,
    source    text,
    geom      geography(LineString, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS segments_geom ON segments USING gist (geom);

-- One row per upload, for the per-install rate limit. install is a SHA-256 of the app's
-- random per-install UUID, so even that never sits in the database as sent.
CREATE TABLE IF NOT EXISTS rides (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    install   text NOT NULL,
    received  timestamptz NOT NULL DEFAULT now(),
    started   timestamptz,
    ended     timestamptz,
    demo      boolean NOT NULL,
    synthetic boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS rides_install ON rides (install, received);

CREATE TABLE IF NOT EXISTS ride_points (
    time         timestamptz NOT NULL,
    ride_id      uuid NOT NULL,
    geom         geography(Point, 4326) NOT NULL,
    speed        real,
    segment_id   text,
    km_from_prev double precision NOT NULL DEFAULT 0,
    demo         boolean NOT NULL,
    synthetic    boolean NOT NULL DEFAULT false
);
SELECT create_hypertable('ride_points', by_range('time'), if_not_exists => true);

CREATE TABLE IF NOT EXISTS near_misses (
    time       timestamptz NOT NULL,
    ride_id    uuid NOT NULL,
    geom       geography(Point, 4326) NOT NULL,
    cls        text NOT NULL,
    level      smallint NOT NULL,
    side       text NOT NULL,
    gap_m      real,
    ttc_s      real,
    speed      real,
    segment_id text,
    demo       boolean NOT NULL,
    synthetic  boolean NOT NULL DEFAULT false
);
SELECT create_hypertable('near_misses', by_range('time'), if_not_exists => true);
CREATE INDEX IF NOT EXISTS near_misses_ride ON near_misses (ride_id);

-- Nearest segment within 25 m, else null. Used on insert and when segments are replaced.
CREATE OR REPLACE FUNCTION match_segment(g geography) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT id FROM segments WHERE ST_DWithin(geom, g, 25) ORDER BY geom <-> g LIMIT 1
$$;

CREATE OR REPLACE FUNCTION set_segment() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.segment_id := match_segment(NEW.geom);
    RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER ride_points_segment BEFORE INSERT ON ride_points
    FOR EACH ROW EXECUTE FUNCTION set_segment();
CREATE OR REPLACE TRIGGER near_misses_segment BEFORE INSERT ON near_misses
    FOR EACH ROW EXECUTE FUNCTION set_segment();

-- Real-time continuous aggregates: materialized_only = false, so a ride POSTed a second
-- ago is already in the totals. demo and synthetic are kept as groups so the public map
-- can leave demo rides out and label modelled data.
CREATE MATERIALIZED VIEW IF NOT EXISTS segment_km_hourly
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT time_bucket('1 hour', time) AS bucket, segment_id, demo, synthetic,
       sum(km_from_prev) AS km
FROM ride_points
GROUP BY bucket, segment_id, demo, synthetic
WITH NO DATA;

CREATE MATERIALIZED VIEW IF NOT EXISTS segment_passes_hourly
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT time_bucket('1 hour', time) AS bucket, segment_id, demo, synthetic,
       count(*) AS passes, max(level) AS worst_level
FROM near_misses
GROUP BY bucket, segment_id, demo, synthetic
WITH NO DATA;

-- The newest hour stays real-time; older buckets (late offline uploads, reloads) are
-- refreshed every 5 minutes.
SELECT add_continuous_aggregate_policy('segment_km_hourly', start_offset => NULL,
    end_offset => INTERVAL '1 hour', schedule_interval => INTERVAL '5 minutes', if_not_exists => true);
SELECT add_continuous_aggregate_policy('segment_passes_hourly', start_offset => NULL,
    end_offset => INTERVAL '1 hour', schedule_interval => INTERVAL '5 minutes', if_not_exists => true);
