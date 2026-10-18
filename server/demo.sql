-- Demo queries for Tiger Cloud's SQL editor. Run one block at a time.

-- (a) The 5 newest near misses, demo rides included: a ride POSTed from the app shows here
--     within seconds of the rider tapping Exit.
SELECT n.time AT TIME ZONE 'America/Toronto' AS local_time,
       round(extract(epoch FROM now() - n.time)) AS seconds_ago,
       coalesce(s.street, '(no street within 25 m)') AS street,
       n.cls, n.level, round(n.gap_m::numeric, 2) AS gap_m,
       CASE WHEN n.synthetic THEN 'synthetic' WHEN n.demo THEN 'demo' ELSE 'real' END AS source
FROM near_misses n
LEFT JOIN segments s ON s.id = n.segment_id
ORDER BY n.time DESC
LIMIT 5;

-- (b) Top 10 streets by close passes per 100 km ridden at evening rush (16:00-18:59 Toronto
--     time), from the real-time continuous aggregates: a new ride counts the moment it lands.
--     Demo rides included so the live demo moves the ranking; add AND NOT demo to both
--     subqueries for the public figure. Edit the hours to rank another time of day.
WITH km AS (
    SELECT segment_id, sum(km) AS km FROM segment_km_hourly
    WHERE extract(hour FROM bucket AT TIME ZONE 'America/Toronto') BETWEEN 16 AND 18
    GROUP BY 1),
passes AS (
    SELECT segment_id, sum(passes) AS passes FROM segment_passes_hourly
    WHERE extract(hour FROM bucket AT TIME ZONE 'America/Toronto') BETWEEN 16 AND 18
    GROUP BY 1)
SELECT s.street,
       string_agg(DISTINCT s.lane_type, ', ') AS lane_types,
       round(sum(km.km)::numeric, 1) AS km_ridden,
       coalesce(sum(p.passes), 0) AS close_passes,
       round((100 * coalesce(sum(p.passes), 0) / sum(km.km))::numeric, 1) AS per_100km
FROM segments s
JOIN km ON km.segment_id = s.id
LEFT JOIN passes p ON p.segment_id = s.id
GROUP BY s.street
HAVING sum(km.km) >= 2
ORDER BY per_100km DESC
LIMIT 10;

-- (b, live) The same ranking over all hours, for the live demo: one new pass moves its
--     street's rate straight away (at a single hour few streets have the 2 km of riding).
WITH km AS (SELECT segment_id, sum(km) AS km FROM segment_km_hourly GROUP BY 1),
passes AS (SELECT segment_id, sum(passes) AS passes FROM segment_passes_hourly GROUP BY 1)
SELECT s.street,
       string_agg(DISTINCT s.lane_type, ', ') AS lane_types,
       round(sum(km.km)::numeric, 1) AS km_ridden,
       coalesce(sum(p.passes), 0) AS close_passes,
       round((100 * coalesce(sum(p.passes), 0) / sum(km.km))::numeric, 1) AS per_100km
FROM segments s
JOIN km ON km.segment_id = s.id
LEFT JOIN passes p ON p.segment_id = s.id
GROUP BY s.street
HAVING sum(km.km) >= 2
ORDER BY per_100km DESC
LIMIT 10;

-- (c) Once the City file is loaded (tools/load_segments.py --source city): close passes
--     per 100 km by lane type, then by ward. Demo rides left out; synthetic split out.
WITH km AS (SELECT segment_id, synthetic, sum(km) AS km FROM segment_km_hourly WHERE NOT demo GROUP BY 1, 2),
passes AS (SELECT segment_id, synthetic, sum(passes) AS passes FROM segment_passes_hourly WHERE NOT demo GROUP BY 1, 2)
SELECT s.lane_type, km.synthetic,
       round(sum(km.km)::numeric, 1) AS km_ridden,
       coalesce(sum(p.passes), 0) AS close_passes,
       round((100 * coalesce(sum(p.passes), 0) / nullif(sum(km.km), 0))::numeric, 1) AS per_100km
FROM segments s
JOIN km ON km.segment_id = s.id
LEFT JOIN passes p ON p.segment_id = s.id AND p.synthetic = km.synthetic
GROUP BY s.lane_type, km.synthetic
ORDER BY km.synthetic, per_100km DESC;

WITH km AS (SELECT segment_id, synthetic, sum(km) AS km FROM segment_km_hourly WHERE NOT demo GROUP BY 1, 2),
passes AS (SELECT segment_id, synthetic, sum(passes) AS passes FROM segment_passes_hourly WHERE NOT demo GROUP BY 1, 2)
SELECT s.ward, s.ward_name, km.synthetic,
       round(sum(km.km)::numeric, 1) AS km_ridden,
       coalesce(sum(p.passes), 0) AS close_passes,
       round((100 * coalesce(sum(p.passes), 0) / nullif(sum(km.km), 0))::numeric, 1) AS per_100km
FROM segments s
JOIN km ON km.segment_id = s.id
LEFT JOIN passes p ON p.segment_id = s.id AND p.synthetic = km.synthetic
WHERE s.ward IS NOT NULL
GROUP BY s.ward, s.ward_name, km.synthetic
HAVING sum(km.km) >= 2
ORDER BY km.synthetic, per_100km DESC;
