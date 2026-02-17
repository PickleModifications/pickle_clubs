# pickle_clubs install notes

## Clubs and entities now use SQL

- Clubs and their entities are now stored in SQL tables:
  - `pickle_clubs`
  - `pickle_club_entities`
- Tables are auto-created at runtime in `modules/main/server.lua`.

## Management module removal

- `modules/management` has been removed.
- Use `/managebar` to open the new club/entity management menu.
- Bartender stations are now bartender entities attached to clubs.

## Fresh-start data behavior

- Legacy `pickle_bartender_stations` data is not migrated.
- Start by creating clubs and bartender entities with the new management flow.
