# Data and privacy

## Where the data lives

- **In Canada.** The near-miss database is a Tiger Cloud service in AWS Canada (Central),
  Montreal (`ca-central-1`), and the server that receives each ride runs in Vercel's Montreal
  region (`yul1`) beside it.
- **Anonymous by design.** No account and no name. The app sends a random per-install id, and
  the database keeps only a hash of it. No video ever leaves the bike. The first and last 50 m
  of every ride are cut on the phone, and the public map (the server's GeoJSON) never shows a
  ride's track: only totals per street, and near misses not linked to any ride or rider.
- **Zero effort for the rider.** One consent tick at setup, then each ride uploads by itself
  when it ends. Offline rides wait and upload on the next launch. A very long ride (over 5.5 h)
  is sent in parts, so nothing is cut.
- **Home and Work never leave the phone.** Saved places and recent destinations are stored on
  the phone itself, like any app's settings.

## The missing denominator

The City records outcomes (cyclists killed or seriously injured) and infrastructure (where the
lanes are), but not exposure: how many people ride each street. Without it, nobody can honestly
say one street is more dangerous than another; downtown has more injuries largely because more
people ride there. 4sight adds the two missing pieces:

1. **Exposure:** kilometres actually ridden on every street, from each ride's GPS.
2. **A leading indicator:** close passes happen far more often than injuries, so they show
   danger before someone gets hurt, not after.

Together: close passes per 100 km ridden, by lane type (protected, painted, shared, none) and by
ward. Rides arrive as a time series and every row is a point on a street, so Tiger Cloud handles
both in one database: hypertables for the stream, PostGIS to match each point to a street and a
ward as it lands, and real-time continuous aggregates so per-street totals are always current.

## How to read the numbers

- A near miss is an approach alert from the rear camera (alert level, time to contact), not a
  surveyed gap in metres.
- Lanes are never claimed to cause or prevent injuries; the point is that decisions about bike
  lanes are being made without near-miss or exposure data.
- Synthetic data is always labelled as example data, and practice rides as test rides.
- The first real rides (18 October 2026, about 1 km near the Pan Am Centre and UTSC) logged
  8 close passes, all by cars. That is far too little riding for a per-100-km rate.

## City of Toronto figures

- 155 cyclists killed or seriously injured in Toronto, 2022 to mid-October 2026: 142 seriously
  injured, 13 killed (City of Toronto Vision Zero).
- 4 downtown wards (Spadina-Fort York, University-Rosedale, Toronto-Danforth, Toronto Centre)
  account for 66 of the 155.
- The City's network today: about 148 km protected, 142 km painted, 208 km shared, 341 km trails.
- Planned 2025 to 2027: about 546 km, mostly in Scarborough, North York and York.
