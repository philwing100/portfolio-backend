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

// Update list object (parent_page/date) or make a new one
const createList = async function createList(req, res) {
  try {
    const listData = parseJsonIfString(req.body?.data, req.body?.data);
    const { parent_page: parentPage, date: listDate, lists } = listData || {};
    const userId = req.user.id;

    if (!userId) {
      return res.status(400).json({ message: 'User not authenticated' });
    }

    if (!parentPage || !listDate || !Array.isArray(lists)) {
      return res.status(400).json({ message: 'Invalid list data' });
    }

    const promisePool = pool.promise();
    await promisePool.query(
      'CALL Update_list_object(?, ?, ?, ?)',
      [userId, parentPage, listDate, JSON.stringify(lists)]
    );

    return res.status(201).json({ message: 'List created successfully' });
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
          lists: parseJsonIfString(row.lists_json, [])
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
