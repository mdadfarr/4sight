# Pitch notes

Points to work into the pitch, with the fact behind each one.

## Data and privacy

- **Toronto riders' data stays in Canada.** The near-miss database is a Tiger Cloud service in
  AWS Canada (Central), Montreal (`ca-central-1`). A good line for the School of Cities judges
  and the City: rider safety data about Toronto streets is stored in Canada.
- **Anonymous by design.** No account and no name. The app sends a random per-install id, and
  the database keeps only a hash of it. No video ever leaves the bike. The first and last 200 m
  of every ride are cut on the phone, so a ride never shows where someone lives or works.
- **Zero effort for the rider.** One consent tick at setup, then each ride uploads by itself
  when it ends. Offline rides wait and upload on the next launch.

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
