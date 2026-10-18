# 4sight server

Two endpoints over Tiger Cloud (TimescaleDB + PostGIS), built to `docs/DATA_PIPELINE.md`:

- `POST /v1/rides`: one finished ride from the front phone. Validated, rate-limited
  (30 rides per install per hour), inserted with parameterised SQL. Each point and near
  miss is matched to the nearest street segment within 25 m by a table trigger.
- `GET /v1/city-risk.geojson`: street segments with close passes per 100 km (segments
  with at least 2 km ridden) and the newest 500 passes. Open CORS, cached 60 s.
  `?demo=1` includes demo rides.

The server is the only thing holding `DATABASE_URL`. The app, the website and this repo
never see it. Never commit it or paste it anywhere public.

Files: `api/rides.py`, `api/city_risk.py` (Vercel Python functions), `api/_store.py`
(validation, insert, GeoJSON; also used by the loaders), `schema.sql`, `demo.sql`,
`dev.py` (both endpoints on a local port), `test_store.py` (validation checks, no database).

## 1. Database (once)

Create a Tiger Cloud service (TimescaleDB, with PostGIS available), then in this terminal:

```bash
export DATABASE_URL="$(cat ~/.4sight-db)"   # the service's connection string, saved privately
uv run --with 'psycopg[binary]' python -c "import os,psycopg; c=psycopg.connect(os.environ['DATABASE_URL'], autocommit=True); c.execute(open('server/schema.sql').read()); print('schema ok')"
uv run --with 'psycopg[binary]' tools/load_segments.py --source osm    # 518 OSM street segments
uv run --with 'psycopg[binary]' tools/load_synthetic.py                # modelled rides, synthetic = true
```

(`psql "$DATABASE_URL" -f server/schema.sql` does the same if psql is installed.)

When the City file lands (`data/city/segments.geojson`), switch over with one command. It
replaces the OSM segments and re-matches every stored point and near miss:

```bash
uv run --with 'psycopg[binary]' tools/load_segments.py --source city
```

## 2. Deploy (Vercel)

```bash
cd server
npx vercel@latest link            # new project, root = server/
npx vercel@latest env add DATABASE_URL production   # paste the connection string when asked
npx vercel@latest deploy --prod
```

The deploy prints the base URL, e.g. `https://4sight-server.vercel.app`. Point the clients at it:

- App: `CityAPI.base` in `4sight/Front/CityUploader.swift` (that one line).
- Website: open `web/index.html?api=<BASE>` (add `&demo=1` to include demo rides), or set the
  default `API` in `web/app.js`.

Without Vercel, the same handlers run locally for the simulator:
`uv run --with 'psycopg[binary]' server/dev.py 8787`, base `http://localhost:8787`.

## 3. Test end to end

```bash
BASE=https://4sight-server.vercel.app          # or http://localhost:8787
uv run --with 'psycopg[binary]' server/test_store.py
python3 tools/demo_ride.py | curl -sS -X POST "$BASE/v1/rides" -H 'Content-Type: application/json' --data @-
# -> {"ride_id": "…", "events": 1}
curl -sS "$BASE/v1/city-risk.geojson?demo=1" | python3 -c "import json,sys; f=json.load(sys.stdin)['features']; print([x['properties'] for x in f if x['properties'].get('demo')][:1])"
```

The demo ride is ~300 m along Ellesmere Road by the Pan Am Centre, ending now, with one
close pass by a car near 43.7864, -79.1890. Then in Tiger Cloud's SQL editor run
`server/demo.sql`:

- (a) newest near misses: the demo pass at the top, seconds old, on Ellesmere Road;
- (b) street ranking per 100 km at evening rush, the public figure;
- (b, live) the same ranking over all hours: run it before and after the demo ride and
  Ellesmere Road's close passes and rate go up;
- (c) by lane type and by ward, once the City file is loaded.

Live demo with the app: preview ride in the simulator (`scripts/front-preview.sh`) or a real
front phone → Exit → "1 near miss added to Toronto's safety map" → (a) shows it → (b)
updates → the app's close-pass map and the website show it.
