# Portfolio Backend — Agent Context

A Node.js/Express REST API for a personal productivity app. Handles user auth, list management, and habit streak tracking. Deployed to Vercel (serverless), backed by MySQL.
The frontend can be found at [github.com/philwing100/](https://github.com/philwing100/portfolio-vue-frontend)
Which is useful for its api docs.

---

## Stack

- **Runtime:** Node.js, Express 4
- **Database:** MySQL via `mysql2` (promise API), all queries go through stored procedures
- **Auth:** Google OAuth 2.0 (passport) + dual JWT (access + refresh tokens)
- **Deployment:** Vercel (`vercel.json` routes everything to `app.js`)

---

## Project Layout

```
app.js                    Entry point, middleware setup, JWT guard
helpers.js                Date/JSON utility functions
databaseConnection/
  database.js             MySQL connection pool
routes/
  index.js                Aggregates all routes under /api
  auth.js                 Google OAuth + JWT token endpoints
  lists.js                List CRUD
  streaks.js              Habit streak tracking
stored_procedures/        22 .sql files defining every DB operation
```

---

## Environment Variables

```
# Database
host, user, password, name, port

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

All routes: `POST /api/<resource>/` with `{ action: 'operationName', data?, params? }` body pattern.

### Auth (`/api/auth`)
| Route | Method | Purpose |
|---|---|---|
| `/google` | GET | Start OAuth |
| `/google/callback` | GET | OAuth callback |
| `/refresh` | POST | Rotate refresh token |
| `/check-auth` | GET | Validate token, return user |
| `/logout` | POST | Revoke refresh token |

### Lists (`/api/lists`)
| Action | Purpose |
|---|---|
| `createList` | Upsert list by `parent_page` + `date` |
| `getList` | Fetch list by `parent_page` + `date`, or by `title` (legacy) |

### Streaks (`/api/streaks`)
| Action | Purpose |
|---|---|
| `getStreaks` | Fetch all streaks; auto-resets any streak not updated in 7+ days |
| `incrementStreak` | Increment count (idempotent — once per day) |
| `updateStreak` | Upsert streak metadata |
| `deleteStreak` | Delete a streak |

---

## Database Schema (key tables)

**`lists`**
- `listID`, `userID` (FK), `parent_page` (VARCHAR), `list_date` (DATE)
- `lists_json` (JSON) — full list payload
- `list_timestamp` (DATETIME), `last_modified` (auto-update)
- UNIQUE: `(userID, parent_page, list_date)`

**`listitems`**
- `itemID`, `parentlistID` (FK), `parent_itemID` (nullable FK — nesting)
- `textString`, `completed`, `scheduledDate`, `dueDate`, `recurringTask`, etc.

**`streaks`**
- `streakID`, `userID`, `title`, `currentStreak`, `highestStreak`
- `days` (TINYINT bitmask — which days of week), `lastUpdated` (DATE), `color`

**`sessions`**
- `sessionID` (UUID), `userID`, `refresh_token_hash` (SHA256), `refresh_token_expires`
- `refresh_token_revoked`, `refresh_token_replaced_by` — supports token rotation chain

---

## Key Patterns

**Action-dispatch routes:** Single `POST` endpoint per resource; `action` field selects operation.

**Stored procedures for all DB work:** No raw SQL in route files. All queries call stored procs defined in `stored_procedures/`.

**Duplicate detection on lists:** `stableStringify()` + `normalizeValue()` in `helpers.js` produce deterministic JSON for comparison before upsert.

**Streak auto-reset:** `getStreaks` checks `lastUpdated`; if >7 days ago, calls `Reset_streaks_by_IDs` before returning.

**Two list addressing schemes:**
- **Current:** `parent_page` + `date` → `Update_list_object` / `Fetch_list_object`
- **Legacy:** `title` → `Update_list` / `Fetch_list` (still supported)

**Timestamp helpers (helpers.js):**
- `toMySqlDateTime(iso)` — ISO → MySQL DATETIME string
- `toIsoTimestamp(mysql)` — MySQL DATETIME → ISO 8601
- `normalizeDate(dt)` — any datetime → `YYYY-MM-DD`
- `getTodayDate()` — today as `YYYY-MM-DD`

---

## Dev Notes

- `npm run dev` uses nodemon; `npm start` for production
- Frontend origins: `http://localhost:8080` (dev) / `https://phillip-ring.vercel.app` (prod)
- `passport-local` and `passport-google-oidc` are installed but unused
- `express-validator` is imported in auth.js but not used
- The app exports itself as a module when `FRONTENDPORT != 3000` (Vercel serverless requirement)
