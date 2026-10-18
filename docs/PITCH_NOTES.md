# Pitch notes

Points to work into the pitch, with the fact behind each one.

## Data and privacy

- **Toronto riders' data stays in Canada.** The near-miss database is a Tiger Cloud service in
  AWS Canada (Central), Montreal (`ca-central-1`). A good line for the School of Cities judges
  and the City: rider safety data about Toronto streets is stored in Canada.
- **Anonymous by design.** No account and no name. The app sends a random per-install id, and
  the database keeps only a hash of it. No video ever leaves the bike. The first and last 50 m
  of every ride are cut on the phone, and the live public map (the server's
  GeoJSON) never shows a ride's track: only totals per street, and near misses not linked to
  any ride or rider.
- **Zero effort for the rider.** One consent tick at setup, then each ride uploads by itself
  when it ends. Offline rides wait and upload on the next launch. A very long ride (over 5.5 h)
  is sent in parts, so nothing is cut.
- **Home and Work never leave the phone.** Saved places and recent destinations are stored on
  the phone itself, like any app's settings. There is no account because nothing about the
  rider needs to be on a server.

## How 4sight data upgrades each track

**School of Cities: the missing denominator.** The City records outcomes (cyclists killed or
seriously injured) and infrastructure (where the lanes are), but not exposure: how many people
ride each street. Without it, nobody can honestly say one street is more dangerous than another;
downtown has more injuries largely because more people ride there. 4sight adds the two missing
pieces:
1. **Exposure:** kilometres actually ridden on every street, from each ride's GPS.
2. **A leading indicator:** close passes happen far more often than injuries, so they show
   danger before someone gets hurt, not after.

Together: close passes per 100 km ridden, by lane type (protected, painted, shared, none) and by
ward. Near misses close to past KSI sites support the method; clusters on streets with no KSI
history are the early warning.

**MLH Best Use of Tiger Data: a live time series on a map.** Rides arrive continuously (time) and
every row is a point on a street (place). Tiger Cloud does both in one database: hypertables for
the stream, PostGIS to match each point to a street and a ward as it lands, and real-time
continuous aggregates so per-street totals are always current. Every ride makes the ranking more
meaningful. The live moment: tap Exit, run query (a) and see a row seconds old, run (b, live) and
watch the street ranking move.

**Best AI for Social Impact: one alert, two jobs.** The on-device AI (vehicle detection, tracking,
threat prediction) protects one rider now (the grips buzz before a close pass) and everyone
later (each alert becomes anonymous public evidence, with no effort from the rider). Privacy by
design: no video leaves the bike, ride ends are trimmed, no accounts, only a hashed install id.
The more people ride with it, the better the map gets for everyone.

## City of Toronto numbers (verified by the City-data work, real data)

- 155 cyclists killed or seriously injured in Toronto, 2022 to mid-October 2026: 142 seriously
  injured, 13 killed (City of Toronto Vision Zero).
- 4 downtown wards (Spadina-Fort York, University-Rosedale, Toronto-Danforth, Toronto Centre)
  account for 66 of the 155.
- The City's network today: about 148 km protected, 142 km painted, 208 km shared, 341 km trails.
- Planned 2025 to 2027: about 546 km, mostly in Scarborough, North York and York.

## Framing (say it this way)

- Never say lanes cause or prevent injuries. The City has no counts of how many people ride
  each street, so downtown has more injuries largely because far more people ride there.
  That missing exposure data, close passes per km actually ridden, is the gap 4sight fills.
- Neutral: "decisions about bike lanes are being made without near-miss data", not for or
  against removing lanes. The challenge asks us not to support a candidate or predict the election.
- A near miss is an approach alert from the rear camera (alert level, time to contact), not a
  surveyed gap in metres. Synthetic data is always labelled synthetic; demo rides, demo.
- One-click question for a councillor's office or a journalist: "where are cyclists hurt in my
  ward, and is the City building lanes there?" Tiger query (e) in server/demo.sql and the
  website's ward panel answer it.
