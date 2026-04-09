//Index.js
const express = require('express');
const router = express.Router();

// Import other route modules
const listsRouter = require('./lists');
const streaksRouter = require('./streaks');
const authRouter = require('./auth');
const flashcardsRouter = require('./flashcards');
//console.log('loaded index.js');

// Define routes
router.use('/lists', listsRouter);
router.use('/streaks', streaksRouter);
router.use('/auth', authRouter);
router.use('/flashcards', flashcardsRouter);

module.exports = router;
