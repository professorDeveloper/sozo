# Roadmap

Ten proposals, each weighed against what the repo already has. The point of
writing it down is the second column: several of these are half-built already,
and one of them is mostly a naming problem rather than a feature.

Sizes are rough and relative — S is a day or two, M is a week, L is longer than
anyone wants to estimate honestly.

---

## 1. Trakt / Letterboxd

**Size: M. Depends on: nothing. Start here.**

AniList and MAL are already integrated (`features/anilist`, 21 files;
`features/mal`, 12), and both land on the same Connections screen. Trakt is the
same shape — OAuth, a library read, a progress write — against an API that,
unlike the other two, covers film and television rather than anime.

That matters because the catalogue is mostly film and series. Today a user
watching a film has nothing to sync to.

What already exists and should be reused rather than re-invented:
`AnilistService.restore()`'s startup flow, the token storage now encrypted by
`SecureBoxes`, and the episode-progress plumbing in `player_page.history.dart`.

Letterboxd has **no public write API**. It can import, not sync. Worth saying
out loud before it is promised.

## 2. Local media server (Jellyfin / Plex / Emby)

**Size: L. Depends on: nothing. High value, high surface.**

Nothing exists for this. It is a genuinely different kind of source — an
authenticated server the user owns, with its own library, transcoding decisions
and playback reporting — so it does not fit the scraper-shaped provider
interface the app has.

The honest shape is a fifth ecosystem beside CloudStream / Aniyomi / Manga /
Mangayomi, with its own credentials per user. Jellyfin first: it is open,
documented, and does not require a paid tier to read a library.

## 3. Better notifications

**Size: S–M. Depends on: nothing. Cheapest real win on this list.**

`features/notifications` exists (11 files) and the backend has a typed
`Notification` model with a push pipeline behind it. What is missing is
occasions, not machinery.

Two bugs found while writing this are worth reading as a warning: both
`streak_risk` and `provider_added` were missing from the model's type enum, so
every notification of those kinds failed validation, was swallowed by a
per-user catch, and the features looked like they had never fired. Anything
added here needs its type registered and a test that asserts the row is
actually written.

## 4. Multi-profile + parental control

**Size: L. Depends on: an account model that has none of this.**

Nothing exists. Every list, history row and setting is keyed to one user. A
profile is a second identity inside an account, which means the history sync,
the private list, the app lock and the download store each need a scope they do
not currently have.

Parental control is the easier half and can ship alone: a content rating filter
plus the existing `app_lock` PIN gating NSFW sources.

## 5. Extension marketplace

**Size: M. Depends on: the catalog work, which is already done.**

This is further along than it looks. `CatalogSource` already harvests every
installable source from all four ecosystems nightly, with language, type, NSFW
and a dead flag; the admin panel browses and verifies it; and a probe now
checks whether each source's site still answers.

What is missing is the user-facing half: the app reads repo indexes directly
rather than this catalogue, so it cannot answer "what is there in French"
without downloading every index first. Exposing the catalogue to the app is a
small API and a screen.

Ratings are the part to be careful with. A star rating on a third-party scraper
is a promise about somebody else's uptime.

## 6. Advanced stats + yearly recap

**Size: S for stats, M for recap. Depends on: nothing.**

`WatchStatsPage` and `WatchStatsStore` already exist and are reachable from four
places. The data is there; what is thin is the presentation.

A recap is a different job from a stats page: it is one story, generated once a
year, and it needs a year of history to tell it. History sync exists, so the
data will be there — for users who have been signed in a year.

## 7. Better watch party

**Size: M. Depends on: nothing.**

`features/watch_party` is 19 files and works: rooms, host control, sync. Chat,
reactions and room history are additive and mostly a socket schema plus a
panel. The player already has a party panel to put them in
(`player_page.party.dart`).

## 8. Voice search on TV and desktop

**Size: S. Depends on: nothing.**

`voice_search_button.dart` and `voice_search_dialog.dart` exist and work on
mobile. `speech_to_text` declares macOS support; TV needs the remote's own mic
button, which is a platform channel rather than a new feature.

## 9. Download scheduling + smart queue

**Size: M. Depends on: nothing.**

`features/download` is 34 files with its own storage layer, transfer data source
and integrity sweep. Wi-Fi-only, a storage cap and auto-fetching new episodes
are policies on top of a queue that already exists.

One caution from this week: the storage root resolver treated an unset location
as the path `''`, which produced `/downloads` at the filesystem root and failed
on both Android and macOS. Anything that adds a second place to configure the
location should go through one resolver.

## 10. Quick wins

Done, or nearly:

- **Language** — was a dropdown over eleven scripts; now the page first run
  already used.
- **Profile grouping** — "Source" and "Extension sources" differed by one word
  and led to two different places; now "Change source" and "All sources".
- **Stats** — already reachable from four places; the item was based on a
  stale reading of the code.
- **Sources** — one screen, three modes, browse in place, and a way to switch
  from what you are looking at.

Still open:

- **Guest state** — what a signed-out user sees is inconsistent: Watch Party is
  hidden, other doors open onto a sign-in wall.
- **Appearance** — colour, font and density exist as a page; the density
  control in particular does less than it claims.

---

## Order

1. Notifications and the remaining quick wins — small, and they fix things that
   are currently wrong rather than adding things that are missing.
2. Trakt — the biggest gap between what the catalogue serves and what the app
   can track.
3. Extension marketplace — most of it is built; it needs exposing.
4. Jellyfin — the largest single piece of new value, and the largest piece of
   work.
5. Multi-profile — last, because it touches every store in the app.
