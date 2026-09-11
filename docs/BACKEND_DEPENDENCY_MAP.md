# KAIZOKU — BACKEND DEPENDENCY MAP & API SPECIFICATION

> **Backend Target:** `https://apisozo.azamov.me/api` (WebSocket Origin: `https://apisozo.azamov.me`)  
> **Source Location:** `lib/core/constants/app_constants.dart` (`baseUrl`, `socketOrigin`)  
> **Investigation Gate:** Zero secrets or credentials exposed. Objective mapping of dependencies, token lifecycles, and offline independence.

---

## 1. BACKEND ROLE & TOPOLOGY

The backend at `apisozo.azamov.me` fulfills two distinct functions in the architecture:
1. **Server-Side Content Provider Proxy (`vidapi`):** Scrapes and indexes video content, resolves protected video mirrors, and returns structured JSON catalogues.
2. **Central User Account & Sync Server:** Manages user registration, JWT authentication sessions, cloud bookmarks, comments, notifications, watch streak tracking, and WatchParty WebSocket signaling.

### 1.1 Is the Backend Mandatory?
* **For Default Out-of-the-Box Experience:** **YES.** A brand new user launching the app in Video Mode with default provider `vidapi` connects to `apisozo.azamov.me` to load the Home catalogue and resolve stream links.
* **For Alternative & Local Workflows:** **NO.** The application is explicitly architected to operate with or without this backend:
  - **Manga & Comics:** Completely independent. Connects directly to Keiyoushi / Mangayomi repositories.
  - **Aniyomi & CloudStream Extensions:** Run on-device via DexClassLoader. Completely independent.
  - **BitTorrent Search & Streaming:** Scrapes public trackers directly and streams via embedded Go TorrServer.
  - **Trackers (AniList / MyAnimeList):** Connect directly to AniList GraphQL and MyAnimeList REST APIs.
  - **Offline Library:** Downloaded media, watch history, and private lists are 100% device-local.

---

## 2. EXHAUSTIVE ENDPOINT INVENTORY

| Endpoint | Method | Auth Required? | Feature Subsystem | Payload / Query Parameters |
|---|:---:|:---:|---|---|
| `/contents/home` | GET | No | Home Catalogue | Returns categories, hero banners, trending items |
| `/contents/genres` | GET | No | Discovery / Filters | Returns available cinema genres |
| `/contents/:type` | GET | No | Catalogue / View All | `page=<int>`, e.g. `/contents/movies`, `/contents/series` |
| `/contents/:type/:slug` | GET | No | Genre Specific View | `page=<int>`, e.g. `/contents/anime/action` |
| `/contents/detail` | GET | No | Title Details | `url=<string>&provider=<id>` |
| `/contents/episodes` | GET | No | Episode Listing | `url=<string>&page=<n>&size=<n>&sort=<asc/desc>` |
| `/contents/media` | GET | No | Stream Link Resolution | `ref=<string>&provider=<id>&lang=<sub/dub>` |
| `/contents/providers` | GET | No | Provider List | Skips auth; returns available server providers |
| `/auth/login` | POST | No | User Sign-In | `identifier`, `password` -> returns `accessToken`, `refreshToken` |
| `/auth/google` | POST | No | Google OAuth Login | `idToken` (Firebase) -> returns session tokens |
| `/auth/register` | POST | No | User Registration | `email`, `username`, `password` -> sends OTP |
| `/auth/register/verify` | POST | No | OTP Verification | `email`, `otp` -> returns session tokens |
| `/auth/register/resend` | POST | No | Resend OTP Code | `email` |
| `/auth/forgot-password` | POST | No | Password Reset Request| `email` |
| `/auth/reset-password` | POST | No | Reset Password Submit | `email`, `otp`, `newPassword` |
| `/auth/refresh` | POST | Refresh Token | Token Rotation | `refreshToken` -> returns new token pair |
| `/auth/profile` | GET/PUT | Bearer Token | User Profile | Update username, avatar |
| `/auth/favorites` | GET/POST/DEL | Bearer Token | Cloud Bookmarks | Fetch favorites list, add/remove `contentUrl` |
| `/auth/lists/:slug` | GET/POST/DEL | Bearer Token | Curated Lists | `watch-later`, `watched` collections |
| `/auth/devices` | GET/DEL | Bearer Token | TV Paired Devices | List and unpair linked TVs |
| `/comments/:id` | GET/POST/DEL | Bearer Token | Discussion Threads | Post comments, reply, delete |
| `/comments/:id/like` | POST | Bearer Token | Comment Reactions | Toggle comment like |
| `/notifications` | GET/DEL | Bearer Token | Push Alerts | List user alerts, unread counts, mark read |
| `/notifications/unread-count`| GET | Bearer Token | Unread Badge Counter | Polled on app open |
| `/shorts/feed` | GET | No | Vertical Video Feed | Paginated reel metadata |
| `/shorts/:id/view` | POST | No | Video View Counter | Increment short view |
| `/shorts/:id/like` | POST | Bearer Token | Short Like Reaction | Toggle like |
| `/streak/status` | GET | Bearer Token | Daily Watch Streak | Retrieve weekly streak calendar |
| `/streak/increment` | POST | Bearer Token | Watch Activity Log | Record active viewing session |
| `/trivia/rounds` | POST/GET | Bearer Token | Quiz Rounds | Create/resume cinema trivia game |
| `/trivia/leaderboard` | GET | No | Leaderboards | Global trivia player rankings |
| `/trivia/challenges` | POST/GET | Bearer Token | Trivia Challenges | Create/join multiplayer challenge |
| `/channels/categories` | GET | No | Live TV Channels | Returns channel groups and stream URLs |
| `/channels/:id/epg` | GET | No | EPG Program Guide | Daily schedule for channel |
| `/remote/devices` | GET/POST | Bearer Token | TV Remote Control | Query and send D-pad keys to paired TV |
| `/reports` | POST | Optional | Error & Broken Link | Submit report for dead media |

---

## 3. AUTHENTICATION & TOKEN LIFECYCLE

1. **Authentication Headers:** Attached via `AuthInterceptor`:
   `Authorization: Bearer <accessToken>`
2. **Expiration & Mutex Refresh:**
   - On receiving HTTP `401 Unauthorized`:
   - `AuthInterceptor` intercepts the response and delegates to `TokenRefresher`.
   - `TokenRefresher` locks an asynchronous mutex to ensure concurrent requests wait for a single refresh call.
   - Executes `POST /auth/refresh` with `refreshToken`.
   - On Success: Saves new `accessToken` and `refreshToken` into Hive `auth_box`, retries the failed request with the new token.
   - On Failure (e.g. refresh token expired or revoked): Emits `AuthSessionExpired()` on `AuthBloc`, clears local auth cache, and redirects router to `/login`.
3. **Guest Mode:**
   - Unauthenticated users can use the app without logging in. Discovery, streaming, local history, local favorites, and local downloads operate seamlessly in Guest mode.

---

## 4. EXTERNAL NON-BACKEND DEPENDENCIES

| Service | Protocol / Endpoint | Purpose | Failure Consequence |
|---|---|---|---|
| **AniList** | `https://graphql.anilist.co` (GraphQL) | Anime library sync & release calendar | Airing reminders pause; streaming unaffected |
| **MyAnimeList** | `https://api.myanimelist.net/v2/` (REST) | MAL watch status sync | MAL sync pauses; streaming unaffected |
| **Keiyoushi Repo** | GitHub raw / index.min.json | Manga extension index & APKs | Extension updates pause; installed work |
| **OpenSubtitles** | `https://api.opensubtitles.com/api/v1/` | Subtitle search & download | Subtitles limited to embedded streams |
| **Google Translate** | Public translation API | Subtitle auto-translation | Subtitles displayed in original language |
| **YouTube** | Direct cipher resolution (YouTubeExplode)| Movie & anime trailer streams | Trailer playback fails gracefully |
| **Nyaa / TokyoToshokan**| Public RSS feeds | Torrent search indexers | Torrent search limited to working trackers |
| **Discord Gateway** | `gateway.discord.gg` / Local IPC | Rich Presence status display | Presence disappears from Discord profile |
