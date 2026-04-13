# Portfolio Backend — Agent Context

A Node.js/Express REST API for a personal productivity app. Handles user auth, list management, habit streak tracking, and flashcard study. Deployed to Vercel (serverless), backed by Supabase (PostgreSQL).
The frontend can be found at [github.com/philwing100/](https://github.com/philwing100/portfolio-vue-frontend)
Which is useful for its api docs.

---

## Stack

- **Runtime:** Node.js, Express 4
- **Database:** PostgreSQL via `pg` (Supabase), all queries go through PostgreSQL functions
- **Auth:** Google OAuth 2.0 (passport) + dual JWT (access + refresh tokens)
- **Deployment:** Vercel (`vercel.json` routes everything to `app.js`)

---

## Project Layout

```
app.js                    Entry point, middleware setup, JWT guard
helpers.js                Date utility functions
databaseConnection/
  database.js             PostgreSQL connection pool (Supabase via DATABASE_URL)
routes/
  index.js                Aggregates all routes under /api
  auth.js                 Google OAuth + JWT token endpoints
  lists.js                List CRUD
  streaks.js              Habit streak tracking
  flashcards.js           Flashcard sets, cards, and SM-2 study sessions
supabase/
  migrations/             4 .sql files: tables, functions, flashcard tables, flashcard functions
stored_procedures/        Legacy MySQL .sql files — no longer used
```

---

## Environment Variables

```
# Database
DATABASE_URL              Supabase connection string (Transaction Pooler, port 6543)

# Auth
JWT_SECRET                  Access token signing secret
JWT_REFRESH_SECRET          Refresh token secret (falls back to JWT_SECRET)
googleClientId              Google OAuth client ID
googleClientSecret          Google OAuth client secret

# Server
FRONTENDPORT                Defaults to 3000; != 3000 means Vercel/prod
NODE_ENV                    "production" enables secure/sameSite=none cookies
```

---

## Auth Flow

**Login:**
1. `GET /api/auth/google` → redirects to Google
2. `GET /api/auth/google/callback` → generates access token (24h) + refresh token (7d)
3. Refresh token stored in HTTP-only cookie; access token passed via redirect URL param

**Token Refresh:**
- `POST /api/auth/refresh` — reads refresh token from cookie, `x-refresh-token` header, or body
- Rotates refresh token (old hash revoked, new hash saved to `sessions` table)

**Protected Routes:**
- All `/api/*` routes except `/api/auth/*` and `/api/*/logout` require `Authorization: Bearer <token>`
- Middleware decodes token and sets `req.user = { id, email }`

**Logout:**
- `POST /api/auth/logout` — revokes refresh token hash in DB, clears cookie

---

## API Endpoints

### Auth (`/api/auth`)
| Route | Method | Purpose |
|---|---|---|
| `/google` | GET | Start OAuth |
| `/google/callback` | GET | OAuth callback |
| `/refresh` | POST | Rotate refresh token |
| `/check-auth` | GET | Validate token, return user |
| `/logout` | POST | Revoke refresh token |

### Lists (`/api/lists`) — action-dispatch POST
| Action | Purpose |
|---|---|
| `createList` | Upsert list by `parent_page` + `date` |
| `getList` | Fetch list by `parent_page` + `date`, or by `title` (legacy) |

### Streaks (`/api/streaks`) — action-dispatch POST
| Action | Purpose |
|---|---|
| `getStreaks` | Fetch all streaks; auto-resets any streak not updated in 7+ days |
| `incrementStreak` | Increment count (idempotent — once per day) |
| `updateStreak` | Upsert streak metadata |
| `deleteStreak` | Delete a streak |

### Flashcards (`/api/flashcards`) — REST style
| Route | Method | Purpose |
|---|---|---|
| `/sets` | GET | Paginated list of sets (`?page=1&limit=20&folder_id=`) |
| `/sets` | POST | Create a set (`{ title, description?, tags?, folder_id? }`) |
| `/sets/bulk` | POST | Create set + cards from delimited text |
| `/sets/:setId` | GET | Set metadata + all cards |
| `/sets/:setId` | PUT | Update set metadata (`{ title, description?, tags?, folder_id? }`) |
| `/sets/:setId` | DELETE | Delete set and all its cards (cascade) |
| `/sets/:setId/cards` | POST | Add one or more cards (`{ term, definition }` or array) |
| `/cards/all` | GET | All cards for the user across every set (`?page=&limit=`) |
| `/cards/:cardId` | PUT | Update card content; resets SM-2 if content changed |
| `/cards/:cardId` | DELETE | Delete a card |
| `/cards/:cardId/review` | POST | Submit SM-2 grade (0–5), persists new state |
| `/study` | GET | Study session: due cards + new cards (`?tags=&new_limit=20`) |
| `/study/folder/:folderId` | GET | Study session scoped to folder + all subfolders recursively |
| `/folders` | GET | All folders for the user (flat list with `parent_folder_id`) |
| `/folders` | POST | Create folder (`{ title, color?, parent_folder_id? }`) |
| `/folders/:folderId` | PUT | Update folder (`{ title?, color?, parent_folder_id? }`) |
| `/folders/:folderId` | DELETE | Delete folder; children/sets become top-level (SET NULL) |

---

## Database Schema (key tables)

**`users`**
- `user_id` (SERIAL PK), `google_id` (VARCHAR UNIQUE), `email` (VARCHAR UNIQUE)

**`sessions`**
- `session_id` (VARCHAR PK), `user_id` (FK), `expires` (BIGINT), `data` (JSONB)
- `refresh_token_hash`, `refresh_token_expires`, `refresh_token_revoked`, `refresh_token_replaced_by`

**`lists`**
- `list_id` (SERIAL PK), `user_id` (FK), `parent_page` (VARCHAR), `list_date` (DATE)
- `lists_json` (JSONB), `list_timestamp` (TIMESTAMP), `last_modified` (auto-update trigger)
- UNIQUE: `(user_id, parent_page, list_date)`

**`listitems`**
- `item_id` (SERIAL PK), `parent_list_id` (FK), `parent_item_id` (nullable FK — nesting)
- `text_string`, `completed`, `scheduled_date`, `due_date`, `recurring_task`, etc.

**`streaks`**
- `streak_id` (SERIAL PK), `user_id` (FK), `title`, `current_streak`, `highest_streak`
- `days` (SMALLINT bitmask — which days of week), `last_updated` (DATE), `color` (CHAR 7)

**`flashcard_folders`**
- `folder_id` (UUID PK), `user_id` (FK), `title`, `color`
- `parent_folder_id` (nullable FK → self, ON DELETE SET NULL) — enables arbitrary nesting
- `created_at`, `updated_at` (auto-update trigger)

**`flashcard_sets`**
- `set_id` (UUID PK), `user_id` (FK), `title`, `description`, `tags` (TEXT[])
- `folder_id` (nullable FK → `flashcard_folders`, ON DELETE SET NULL)
- `created_at`, `updated_at` (auto-update trigger)

**`flashcard_cards`**
- `card_id` (UUID PK), `set_id` (FK → cascade delete), `user_id` (FK)
- `term`, `definition`, `content_hash` (SHA-256 of `term|definition`)
- SM-2 state: `ease_factor` (FLOAT, default 2.5), `interval_days` (INT), `repetitions` (INT), `due_date` (DATE)

---

## Key Patterns

**Action-dispatch routes (lists, streaks):** Single `POST` endpoint per resource; `action` field selects operation.

**REST routes (flashcards):** Standard HTTP verbs on resource URLs — no action-dispatch.

**PostgreSQL functions for all DB work:** No raw SQL in route files (except `COUNT(*)` on flashcards for pagination). All operations call functions defined in `supabase/migrations/`.

**SM-2 spaced repetition:** Grade 0–5 computed in JS (`computeSM2()` in `flashcards.js`), result persisted via `review_flashcard_card()`. Content hash (`SHA-256` of `term|definition`) triggers SM-2 reset on card edit.

**Transactions:** `withTransaction(fn)` helper in `flashcards.js` wraps multi-step operations (bulk create, multi-card insert) in `BEGIN/COMMIT` with automatic rollback.

**Duplicate detection on lists:** `stableStringify()` + `normalizeValue()` in `helpers.js` produce deterministic JSON for comparison before upsert.

**Streak auto-reset:** `getStreaks` checks `last_updated`; if >7 days ago, calls `reset_streaks_by_ids` before returning.

**Two list addressing schemes:**
- **Current:** `parent_page` + `date` → `update_list_object` / `fetch_list_object`
- **Legacy:** `title` → `update_list` / `fetch_list` (still supported)

**Date helpers (helpers.js):**
- `getTodayDate()` — today as `YYYY-MM-DD`
- `normalizeDate(dt)` — any datetime string → `YYYY-MM-DD`
- `getWeekDayFromDate(dt)` — datetime → weekday name string

---

## Dev Notes

- `npm run dev` uses nodemon; `npm start` for production
- Frontend origins: `http://localhost:8080` (dev) / `https://phillip-ring.vercel.app` (prod)
- `passport-local` and `passport-google-oidc` are installed but unused
- `express-validator` is imported in auth.js but not used
- `mysql2` is still in package.json but unused — legacy from MySQL era
- The app exports itself as a module when `FRONTENDPORT != 3000` (Vercel serverless requirement)
- Migrations live in `supabase/migrations/`; apply with `npx supabase db push` (after `supabase login` + `supabase link`) or run directly via `pg` client using `DATABASE_URL`
