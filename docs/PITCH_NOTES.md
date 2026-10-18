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
