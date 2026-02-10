const express = require('express');
const jwt = require('jsonwebtoken');
const pool = require('../databaseConnection/database');
const auth = require('./auth');
const router = express.Router();

const parseJsonIfString = (value, fallback = null) => {
  if (value == null) return fallback;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch (err) {
      return fallback;
    }
  }
  if (typeof value === 'object') return value;
  return fallback;
};

const normalizeValue = (value) => {
  if (Array.isArray(value)) {
    return value.map(normalizeValue);
  }
  if (value && typeof value === 'object') {
    return Object.keys(value)
      .sort()
      .reduce((acc, key) => {
        acc[key] = normalizeValue(value[key]);
        return acc;
      }, {});
  }
  return value;
};

const stableStringify = (value) => JSON.stringify(normalizeValue(value));

const normalizeTimestampInput = (value) => {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
};

const toMySqlDateTime = (isoString) => {
  if (!isoString) return null;
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString().slice(0, 19).replace('T', ' ');
};

const toIsoTimestamp = (value) => {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
};

// Update list object (parent_page/date) or make a new one
const createList = async function createList(req, res) {
  try {
    const listData = parseJsonIfString(req.body?.data, req.body?.data);
    const { parent_page: parentPage, date: listDate, lists, timestamp } = listData || {};
    const userId = req.user.id;

    if (!userId) {
      return res.status(400).json({ message: 'User not authenticated' });
    }

    if (!parentPage || !listDate || !Array.isArray(lists)) {
      return res.status(400).json({ message: 'Invalid list data' });
    }

    const promisePool = pool.promise();
    const [existingRows] = await promisePool.query(
      'CALL Fetch_list_object(?, ?, ?)',
      [userId, parentPage, listDate]
    );

    const existingRow = existingRows?.[0]?.[0];
    if (existingRow) {
      const existingLists = parseJsonIfString(existingRow.lists_json, []);
      const normalizedExisting = stableStringify(existingLists);
      const normalizedIncoming = stableStringify(lists);

      if (normalizedIncoming === normalizedExisting) {
        return res.status(200).json({
          success: true,
          message: 'List unchanged',
          data: {
            parent_page: existingRow.parent_page,
            date: existingRow.list_date,
            lists: existingLists,
            timestamp: toIsoTimestamp(existingRow.list_timestamp)
          }
        });
      }
    }

    const resolvedTimestamp = normalizeTimestampInput(timestamp) || new Date().toISOString();
    const resolvedTimestampDb = toMySqlDateTime(resolvedTimestamp);

    await promisePool.query(
      'CALL Update_list_object(?, ?, ?, ?, ?)',
      [userId, parentPage, listDate, JSON.stringify(lists), resolvedTimestampDb]
    );

    return res.status(201).json({
      success: true,
      message: 'List created successfully',
      data: {
        parent_page: parentPage,
        date: listDate,
        lists,
        timestamp: resolvedTimestamp
      }
    });
  } catch (err) {
    console.error('Error creating list:', err);
    return res.status(500).json({ message: 'Error creating list' });
  }
};

// 2. Read all lists (or one list by ID)
const getList = async function getList(req, res) {
  try {
    const promisePool = pool.promise();
    const userId = req.user.id; // Get the user ID from the JWT token
    const { list_title: listTitle, parent_page: parentPage, date: listDate } = req.body.params || {};

    if (!userId) {
      return res.status(400).json({ message: 'User not authenticated' });
    }

    if (parentPage && listDate) {
      const [rows] = await promisePool.query(
        'CALL Fetch_list_object(?, ?, ?)',
        [userId, parentPage, listDate]
      );

      const row = rows?.[0]?.[0];
      if (!row) {
        return res.json({ success: true, message: 'No list exists for that parent_page/date' });
      }

      return res.json({
        success: true,
        data: {
          parent_page: row.parent_page,
          date: row.list_date,
          lists: parseJsonIfString(row.lists_json, []),
          timestamp: toIsoTimestamp(row.list_timestamp)
        }
      });
    }

    const [lists] = await promisePool.query(
      'CALL Fetch_list(?, ?)', [userId, listTitle]
    );

    if (lists?.[0]?.[0]?.listID != null) {
      const [list_items] = await promisePool.query(
        'CALL Fetch_list_item(?)', lists[0][0].listID
      );

      const merged = { ...lists, ...list_items };
      return res.json({ success: true, data: merged });
    }

    return res.json({ success: true, message: 'No list exists for that title' });
  } catch (error) {
    console.error("Error fetching lists:", error);
    return res.status(500).json({ success: false, error: "Server error" });
  }
};

router.post('/', async (req, res) => {
  const { action } = req.body;
  if (action === 'getList') {
    return getList(req, res);
  } else if (action === 'createList') {
    return createList(req, res);
  }

  res.status(400).json({ error: 'Invalid action' });
});

module.exports = router;
