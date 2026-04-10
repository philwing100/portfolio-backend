# Backend Spec: Missing Flashcard Routes
This is the spec that was written by the frontend claude.
## Context

The frontend flashcard system (`src/views/Study.vue`) uses folders to group sets visually. The backend has no folder concept. Additionally, the `GET /api/flashcards/sets` list endpoint returns `card_count` but not `due_count`, forcing the frontend to either fetch every set individually (N+1) or skip per-set due counts on the home page.

Two additions are needed:
1. Add `due_count` to the existing `GET /api/flashcards/sets` response
2. Add full Folder CRUD under `/api/flashcards/folders`

---

## Paste this into backend Claude

---

I need you to add two things to the existing flashcard routes in `routes/flashcards.js` and a new Supabase migration. Here is the full context of the existing system so you can match patterns exactly.

### Existing patterns to match

**Auth:** All routes use `req.user.id` (integer) extracted from JWT by the global `authenticateJWT` middleware.

**Response envelope:**
```js
// Success
res.json({ success: true, data: <payload> })
res.status(201).json({ success: true, data: <payload> })

// Client error
res.status(400).json({ message: 'description' })
res.status(404).json({ message: 'Not found' })

// Server error
res.status(500).json({ success: false, error: 'Server error' })
```

**Database:** Uses `pool.query(...)` with named Postgres functions (e.g. `SELECT * FROM fetch_flashcard_sets($1, $2, $3)`). All mutations go through stored procedures. Bulk operations use the `withTransaction(async client => { ... })` helper.

**Schema refs:**
- `flashcard_sets(set_id UUID, user_id INT, title VARCHAR, description TEXT, tags TEXT[], created_at, updated_at)`
- `flashcard_cards(card_id UUID, set_id UUID, user_id INT, term, definition, content_hash, ease_factor NUMERIC(4,2), interval_days INT, repetitions INT, due_date DATE, last_reviewed TIMESTAMPTZ, created_at, updated_at)`

---

### Change 1 — Add `due_count` to GET /api/flashcards/sets

**Problem:** The list endpoint returns `card_count` but not `due_count`. The frontend needs per-set due counts on the study home page without fetching every set individually.

**What to do:**

1. Create a new Supabase migration file `supabase/migrations/<timestamp>_add_due_count_to_fetch_sets.sql` that replaces the `fetch_flashcard_sets` function:

```sql
CREATE OR REPLACE FUNCTION fetch_flashcard_sets(
  p_user_id INT,
  p_limit   INT,
  p_offset  INT
) RETURNS TABLE(
  set_id       UUID,
  user_id      INT,
  title        VARCHAR,
  description  TEXT,
  tags         TEXT[],
  created_at   TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ,
  card_count   BIGINT,
  due_count    BIGINT
) AS $$
  SELECT
    s.set_id,
    s.user_id,
    s.title,
    s.description,
    s.tags,
    s.created_at,
    s.updated_at,
    COUNT(c.card_id)                                         AS card_count,
    COUNT(c.card_id) FILTER (
      WHERE c.repetitions > 0 AND c.due_date <= CURRENT_DATE
    )                                                        AS due_count
  FROM  flashcard_sets  s
  LEFT JOIN flashcard_cards c
         ON c.set_id = s.set_id AND c.user_id = p_user_id
  WHERE s.user_id = p_user_id
  GROUP BY s.set_id
  ORDER BY s.created_at DESC
  LIMIT  p_limit
  OFFSET p_offset;
$$ LANGUAGE sql STABLE;
```

2. No JS route changes needed — `due_count` will appear automatically in the rows returned by the existing query.

**New response shape for each set in `GET /api/flashcards/sets`:**
```json
{
  "set_id": "uuid",
  "title": "Spanish Vocabulary",
  "description": "{\"folderId\":1,\"options\":{\"newPerDay\":20,\"orderMode\":\"random\"}}",
  "tags": [],
  "card_count": 42,
  "due_count": 7,
  "created_at": "2026-04-07T10:30:00Z",
  "updated_at": "2026-04-08T15:45:00Z"
}
```

---

### Change 2 — Folder CRUD: /api/flashcards/folders

**Problem:** The frontend has a folder concept (groups of sets with a title and color). The backend has no storage for this. Folders need full CRUD.

**What to do:**

#### 2a. Migration — new table

Create migration `supabase/migrations/<timestamp>_create_flashcard_folders.sql`:

```sql
CREATE TABLE IF NOT EXISTS flashcard_folders (
  folder_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    INT  NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  title      VARCHAR(120) NOT NULL,
  color      VARCHAR(20)  NOT NULL DEFAULT '#4CAF50',
  created_at TIMESTAMPTZ  DEFAULT NOW(),
  updated_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flashcard_folders_user_id
  ON flashcard_folders (user_id);

CREATE OR REPLACE TRIGGER flashcard_folders_updated_at
  BEFORE UPDATE ON flashcard_folders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

**Note:** `set_updated_at()` trigger function already exists from the cards migration — do not redefine it.

#### 2b. Routes — add to `routes/flashcards.js`

Add the following four routes. Match the existing auth, error handling, and response envelope patterns exactly.

```js
// ── Folders ───────────────────────────────────────────────────────────────

// GET /api/flashcards/folders — list all folders for the authenticated user
router.get('/folders', async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT folder_id, user_id, title, color, created_at, updated_at
         FROM flashcard_folders
        WHERE user_id = $1
        ORDER BY created_at ASC`,
      [req.user.id],
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error('Error fetching folders:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// POST /api/flashcards/folders — create a folder
// Body: { title: string, color?: string }
router.post('/folders', async (req, res) => {
  try {
    const { title, color = '#4CAF50' } = req.body;
    if (!title?.trim()) {
      return res.status(400).json({ message: 'title is required' });
    }
    const { rows } = await pool.query(
      `INSERT INTO flashcard_folders (user_id, title, color)
            VALUES ($1, $2, $3)
       RETURNING folder_id, user_id, title, color, created_at, updated_at`,
      [req.user.id, title.trim(), color],
    );
    return res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    console.error('Error creating folder:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// PUT /api/flashcards/folders/:folderId — update title and/or color
// Body: { title?: string, color?: string }
router.put('/folders/:folderId', async (req, res) => {
  try {
    const { folderId } = req.params;
    const { title, color } = req.body;

    if (!title?.trim() && !color) {
      return res.status(400).json({ message: 'Provide title or color to update' });
    }

    const { rows } = await pool.query(
      `UPDATE flashcard_folders
          SET title      = COALESCE(NULLIF($3, ''), title),
              color      = COALESCE($4, color),
              updated_at = NOW()
        WHERE folder_id = $1 AND user_id = $2
       RETURNING folder_id, user_id, title, color, created_at, updated_at`,
      [folderId, req.user.id, title?.trim() ?? '', color ?? null],
    );

    if (!rows[0]) return res.status(404).json({ message: 'Folder not found' });
    return res.json({ success: true, data: rows[0] });
  } catch (err) {
    console.error('Error updating folder:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// DELETE /api/flashcards/folders/:folderId — delete a folder
// Note: sets are NOT deleted; their folderId reference (stored in description JSON)
//       becomes stale and the frontend handles cleanup client-side.
router.delete('/folders/:folderId', async (req, res) => {
  try {
    const { folderId } = req.params;
    const { rowCount } = await pool.query(
      `DELETE FROM flashcard_folders
        WHERE folder_id = $1 AND user_id = $2`,
      [folderId, req.user.id],
    );
    if (rowCount === 0) return res.status(404).json({ message: 'Folder not found' });
    return res.json({ success: true, message: 'Folder deleted' });
  } catch (err) {
    console.error('Error deleting folder:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});
```

---

### Expected response shapes summary

**GET /api/flashcards/folders**
```json
{
  "success": true,
  "data": [
    { "folder_id": "uuid", "user_id": 1, "title": "Languages", "color": "#4CAF50", "created_at": "...", "updated_at": "..." }
  ]
}
```

**POST /api/flashcards/folders** (201)
```json
{ "success": true, "data": { "folder_id": "uuid", "user_id": 1, "title": "Languages", "color": "#4CAF50", "created_at": "...", "updated_at": "..." } }
```

**PUT /api/flashcards/folders/:id** (200)
```json
{ "success": true, "data": { /* updated folder */ } }
```

**DELETE /api/flashcards/folders/:id** (200)
```json
{ "success": true, "message": "Folder deleted" }
```

---

### Notes for the backend dev

- Folder `folder_id` is a UUID (Postgres `gen_random_uuid()`), same as `set_id` and `card_id`.
- The frontend stores `folderId` as part of the set's `description` JSON field (e.g. `{"folderId":"<uuid>","options":{...}}`). The backend does not enforce referential integrity between sets and folders — that's intentional, as it avoids cascade deletes on folders removing all sets.
- Do not add folder endpoints to any existing migration — create a new file with a timestamp after the existing flashcard migrations (`20260407000002` and `20260407000003`).
- Register the new router prefix if needed: the existing `app.use('/api/flashcards', flashcardsRouter)` already covers `/api/flashcards/folders` so no `app.js` changes are required.
