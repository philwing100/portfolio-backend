const express = require('express');
const crypto = require('crypto');
const pool = require('../databaseConnection/database');

const router = express.Router();

// ─── HELPERS ─────────────────────────────────────────────────────────────────

/**
 * SM-2 spaced repetition algorithm.
 * grade 0-2 → failed: reset reps and interval, ease_factor unchanged.
 * grade 3-5 → passed: update ease_factor, increment reps, compute next interval.
 * Returns new SM-2 state ready to be persisted.
 */
function computeSM2(grade, easeFactor, intervalDays, repetitions) {
  let newEf = easeFactor;
  let newInterval;
  let newReps;

  if (grade < 3) {
    newReps = 0;
    newInterval = 1;
    // ease_factor intentionally unchanged on failure (per SM-2 spec)
  } else {
    newEf = Math.max(1.3, easeFactor + 0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02));
    newReps = repetitions + 1;
    if (newReps === 1) {
      newInterval = 1;
    } else if (newReps === 2) {
      newInterval = 6;
    } else {
      newInterval = Math.round(intervalDays * newEf);
    }
  }

  const dueDate = new Date();
  dueDate.setDate(dueDate.getDate() + newInterval);

  return {
    ease_factor: parseFloat(newEf.toFixed(2)),
    interval_days: newInterval,
    repetitions: newReps,
    due_date: dueDate.toISOString().slice(0, 10),
  };
}

/**
 * SHA-256 of "term|definition". Used to detect content changes on card update
 * so SM-2 state can be selectively reset.
 */
function contentHash(term, definition) {
  return crypto.createHash('sha256').update(`${term}|${definition}`).digest('hex');
}

/**
 * Wraps a multi-step DB operation in a BEGIN/COMMIT transaction.
 * Automatically rolls back and releases the client on error.
 */
async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ─── SETS ─────────────────────────────────────────────────────────────────────

/**
 * GET /api/flashcards/sets?page=1&limit=20
 * Returns paginated set list for the authenticated user, each with card_count.
 */
router.get('/sets', async (req, res) => {
  try {
    const userId = req.user.id;
    const page   = Math.max(1, parseInt(req.query.page)  || 1);
    const limit  = Math.min(100, Math.max(1, parseInt(req.query.limit) || 20));
    const offset = (page - 1) * limit;

    const [{ rows: sets }, { rows: countRows }] = await Promise.all([
      pool.query('SELECT * FROM fetch_flashcard_sets($1, $2, $3)', [userId, limit, offset]),
      pool.query('SELECT COUNT(*) FROM flashcard_sets WHERE user_id = $1', [userId]),
    ]);

    const total = parseInt(countRows[0].count, 10);
    return res.json({
      success: true,
      data: sets,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (err) {
    console.error('Error fetching sets:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * POST /api/flashcards/sets
 * Body: { title, description?, tags? }
 * Creates a new flashcard set.
 */
router.post('/sets', async (req, res) => {
  try {
    const userId = req.user.id;
    const { title, description = null, tags = [] } = req.body;

    if (!title) return res.status(400).json({ message: 'title is required' });

    const { rows } = await pool.query(
      'SELECT * FROM create_flashcard_set($1, $2, $3, $4)',
      [userId, title, description, tags],
    );
    return res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    console.error('Error creating set:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * POST /api/flashcards/sets/bulk
 * Body: { title, description?, tags?, content, termDelimiter?, defDelimiter? }
 *
 * Parses `content` into cards using the provided delimiters and atomically
 * creates a new set + all cards in a single transaction.
 *
 * Default delimiters mirror the common Anki TSV export format:
 *   termDelimiter = '\t'  (separates term from definition on a line)
 *   defDelimiter  = '\n'  (separates cards)
 *
 * Example content: "dog\tA domesticated animal\ncat\tA small feline"
 */
router.post('/sets/bulk', async (req, res) => {
  try {
    const userId = req.user.id;
    const {
      title,
      description = null,
      tags = [],
      content,
      termDelimiter = '\t',
      defDelimiter  = '\n',
    } = req.body;

    if (!title)   return res.status(400).json({ message: 'title is required' });
    if (!content) return res.status(400).json({ message: 'content is required' });

    const cards = content
      .split(defDelimiter)
      .map(line => {
        const idx = line.indexOf(termDelimiter);
        if (idx === -1) return null;
        return {
          term:       line.slice(0, idx).trim(),
          definition: line.slice(idx + termDelimiter.length).trim(),
        };
      })
      .filter(c => c && c.term && c.definition);

    if (cards.length === 0) {
      return res.status(400).json({ message: 'No valid cards parsed — check content and delimiters' });
    }

    const result = await withTransaction(async (client) => {
      const { rows: setRows } = await client.query(
        'SELECT * FROM create_flashcard_set($1, $2, $3, $4)',
        [userId, title, description, tags],
      );
      const set = setRows[0];

      const insertedCards = [];
      for (const card of cards) {
        const hash = contentHash(card.term, card.definition);
        const { rows: cardRows } = await client.query(
          'SELECT * FROM insert_flashcard_card($1, $2, $3, $4, $5)',
          [set.set_id, userId, card.term, card.definition, hash],
        );
        insertedCards.push(cardRows[0]);
      }

      return { ...set, cards: insertedCards };
    });

    return res.status(201).json({ success: true, data: result });
  } catch (err) {
    console.error('Error bulk creating set:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * GET /api/flashcards/sets/:setId
 * Returns set metadata and all its cards.
 */
router.get('/sets/:setId', async (req, res) => {
  try {
    const userId = req.user.id;
    const { setId } = req.params;

    const [{ rows: metaRows }, { rows: cardRows }] = await Promise.all([
      pool.query('SELECT * FROM fetch_flashcard_set_meta($1, $2)', [setId, userId]),
      pool.query('SELECT * FROM fetch_flashcard_cards($1, $2)', [setId, userId]),
    ]);

    if (!metaRows[0]) return res.status(404).json({ message: 'Set not found' });
    return res.json({ success: true, data: { ...metaRows[0], cards: cardRows } });
  } catch (err) {
    console.error('Error fetching set:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * PUT /api/flashcards/sets/:setId
 * Body: { title, description?, tags? }
 * Updates set metadata. Does not touch cards.
 */
router.put('/sets/:setId', async (req, res) => {
  try {
    const userId = req.user.id;
    const { setId } = req.params;
    const { title, description = null, tags = [] } = req.body;

    if (!title) return res.status(400).json({ message: 'title is required' });

    const { rows } = await pool.query(
      'SELECT * FROM update_flashcard_set($1, $2, $3, $4, $5)',
      [setId, userId, title, description, tags],
    );
    if (!rows[0]) return res.status(404).json({ message: 'Set not found' });
    return res.json({ success: true, data: rows[0] });
  } catch (err) {
    console.error('Error updating set:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * DELETE /api/flashcards/sets/:setId
 * Deletes set and all its cards (cascade).
 */
router.delete('/sets/:setId', async (req, res) => {
  try {
    const userId = req.user.id;
    const { setId } = req.params;

    const { rows } = await pool.query(
      'SELECT delete_flashcard_set($1, $2) AS deleted',
      [setId, userId],
    );
    if (!rows[0].deleted) return res.status(404).json({ message: 'Set not found' });
    return res.json({ success: true, message: 'Set deleted' });
  } catch (err) {
    console.error('Error deleting set:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── CARDS ────────────────────────────────────────────────────────────────────

/**
 * POST /api/flashcards/sets/:setId/cards
 * Body: { term, definition } OR [{ term, definition }, ...]
 * Adds one or more cards to a set. Multiple cards are inserted in a transaction.
 */
router.post('/sets/:setId/cards', async (req, res) => {
  try {
    const userId = req.user.id;
    const { setId } = req.params;

    const input = Array.isArray(req.body) ? req.body : [req.body];
    const valid = input.filter(c => c.term && c.definition);
    if (valid.length === 0) {
      return res.status(400).json({ message: 'Each card must have term and definition' });
    }

    if (valid.length === 1) {
      const { term, definition } = valid[0];
      const hash = contentHash(term, definition);
      const { rows } = await pool.query(
        'SELECT * FROM insert_flashcard_card($1, $2, $3, $4, $5)',
        [setId, userId, term, definition, hash],
      );
      if (!rows[0]) return res.status(404).json({ message: 'Set not found or access denied' });
      return res.status(201).json({ success: true, data: rows[0] });
    }

    const insertedCards = await withTransaction(async (client) => {
      const results = [];
      for (const { term, definition } of valid) {
        const hash = contentHash(term, definition);
        const { rows } = await client.query(
          'SELECT * FROM insert_flashcard_card($1, $2, $3, $4, $5)',
          [setId, userId, term, definition, hash],
        );
        if (!rows[0]) throw Object.assign(new Error('Set not found or access denied'), { status: 404 });
        results.push(rows[0]);
      }
      return results;
    });

    return res.status(201).json({ success: true, data: insertedCards });
  } catch (err) {
    if (err.status === 404) return res.status(404).json({ message: err.message });
    console.error('Error adding card(s):', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * PUT /api/flashcards/cards/:cardId
 * Body: { term, definition }
 * Updates card content. If the content hash changes, SM-2 state is reset.
 */
router.put('/cards/:cardId', async (req, res) => {
  try {
    const userId = req.user.id;
    const { cardId } = req.params;
    const { term, definition } = req.body;

    if (!term || !definition) {
      return res.status(400).json({ message: 'term and definition are required' });
    }

    const hash = contentHash(term, definition);
    const { rows } = await pool.query(
      'SELECT * FROM update_flashcard_card($1, $2, $3, $4, $5)',
      [cardId, userId, term, definition, hash],
    );
    if (!rows[0]) return res.status(404).json({ message: 'Card not found' });
    return res.json({ success: true, data: rows[0] });
  } catch (err) {
    console.error('Error updating card:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * DELETE /api/flashcards/cards/:cardId
 * Deletes a single card.
 */
router.delete('/cards/:cardId', async (req, res) => {
  try {
    const userId = req.user.id;
    const { cardId } = req.params;

    const { rows } = await pool.query(
      'SELECT delete_flashcard_card($1, $2) AS deleted',
      [cardId, userId],
    );
    if (!rows[0].deleted) return res.status(404).json({ message: 'Card not found' });
    return res.json({ success: true, message: 'Card deleted' });
  } catch (err) {
    console.error('Error deleting card:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * POST /api/flashcards/cards/:cardId/review
 * Body: { grade }  — integer 0-5 (SM-2 quality rating)
 *
 * Grades:
 *   0 — complete blackout
 *   1 — wrong, familiar after seeing answer
 *   2 — wrong, easy after seeing answer
 *   3 — correct, significant difficulty
 *   4 — correct, minor hesitation
 *   5 — perfect recall
 *
 * SM-2 is computed in JS and the result is persisted atomically.
 */
router.post('/cards/:cardId/review', async (req, res) => {
  try {
    const userId = req.user.id;
    const { cardId } = req.params;
    const { grade } = req.body;

    if (grade == null || !Number.isInteger(grade) || grade < 0 || grade > 5) {
      return res.status(400).json({ message: 'grade must be an integer from 0 to 5' });
    }

    const { rows: existing } = await pool.query(
      'SELECT * FROM fetch_flashcard_card($1, $2)',
      [cardId, userId],
    );
    if (!existing[0]) return res.status(404).json({ message: 'Card not found' });

    const card = existing[0];
    const newState = computeSM2(
      grade,
      parseFloat(card.ease_factor),
      card.interval_days,
      card.repetitions,
    );

    const { rows } = await pool.query(
      'SELECT review_flashcard_card($1, $2, $3, $4, $5, $6) AS success',
      [cardId, userId, newState.ease_factor, newState.interval_days, newState.repetitions, newState.due_date],
    );
    if (!rows[0].success) return res.status(404).json({ message: 'Card not found' });

    return res.json({ success: true, data: newState });
  } catch (err) {
    console.error('Error reviewing card:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ─── STUDY SESSION ────────────────────────────────────────────────────────────

/**
 * GET /api/flashcards/study?tags=tag1,tag2&new_limit=20
 *
 * Returns all cards due for review today plus up to new_limit unseen cards.
 * Optionally filter to sets that share any of the provided tags (OR semantics).
 * Omit tags to study across all sets.
 *
 * Response shape:
 *   { success, data: { due: [...], new: [...] } }
 */
router.get('/study', async (req, res) => {
  try {
    const userId = req.user.id;

    const tagsRaw = req.query.tags;
    const tags = tagsRaw
      ? (Array.isArray(tagsRaw) ? tagsRaw : tagsRaw.split(','))
          .map(t => t.trim()).filter(Boolean)
      : [];

    const newLimit = Math.max(0, Math.min(200, parseInt(req.query.new_limit) || 20));

    const { rows } = await pool.query(
      'SELECT * FROM fetch_study_session($1, $2, $3)',
      [userId, tags.length > 0 ? tags : null, newLimit],
    );

    const due      = rows.filter(r => r.card_type === 'review');
    const newCards = rows.filter(r => r.card_type === 'new');

    return res.json({ success: true, data: { due, new: newCards } });
  } catch (err) {
    console.error('Error fetching study session:', err);
    return res.status(500).json({ success: false, error: 'Server error' });
  }
});

module.exports = router;
