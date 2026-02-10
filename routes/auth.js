const express = require('express');
const passport = require('passport');
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const pool = require('../databaseConnection/database'); // Database connection
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const router = express.Router();

const port = process.env.FRONTENDPORT || 3000;
const frontendPath = port == 3000 ? "http://localhost:8080" : "https://phillip-ring.vercel.app";
const accessTokenTtl = '24h';
const refreshTokenTtl = '7d';
const refreshTokenMs = 7 * 24 * 60 * 60 * 1000;
const refreshTokenSecret = process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET;

// Google OAuth strategy
passport.use(new GoogleStrategy({
  clientID: process.env.googleClientId,
  clientSecret: process.env.googleClientSecret,
  callbackURL: '/api/auth/google/callback',
  passReqToCallback: true,
  prompt: 'select_account'
},
  async function googleStrategy(req, accessToken, refreshToken, profile, done) {
    try {
      const googleId = profile.id;
      const email = profile.emails[0].value;

      // Check if the user already exists
      const [results] = await pool.promise().query('SELECT * FROM users WHERE google_id = ?', [googleId]);
      if (results.length > 0) {
        // If user exists, return user
        console.log('retrieving from db' + results[0]);
        return done(null, results[0]);
      } else {
        // If user does not exist, create new user
        await pool.promise().query('INSERT INTO users (google_id, email) VALUES (?, ?)', [googleId, email]);
        const [newUserResults] = await pool.promise().query('SELECT * FROM users WHERE google_id = ?', [googleId]);
        return done(null, newUserResults[0]);
      }
    } catch (err) {
      console.warn('Error during Google authentication:', err);
      return done(err);
    }
  }));

// Google login route
router.get('/google', passport.authenticate('google', {
  scope: ['email'],
  prompt: 'select_account',
  session: false 
}));

// Google callback route
router.get('/google/callback',
  passport.authenticate('google', {
    failureRedirect: '/api/auth/failure',
    session: false 
  }),
  (req, res) => {
    // If authentication is successful, generate a JWT token and redirect to frontend
    const token = jwt.sign(
      { id: req.user.userID, email: req.user.email },  // Create a payload with user data
      process.env.JWT_SECRET,  // Secret key for JWT signing
      { expiresIn: accessTokenTtl }  // Set token expiry time
    );

    const refreshToken = jwt.sign(
      { id: req.user.userID, email: req.user.email },
      refreshTokenSecret,
      { expiresIn: refreshTokenTtl }
    );

    const refreshTokenHash = crypto
      .createHash('sha256')
      .update(refreshToken)
      .digest('hex');

    const sessionId = uuidv4();
    const refreshExpiresAt = new Date(Date.now() + refreshTokenMs);
    const sessionData = JSON.stringify({
      userAgent: req.headers['user-agent'] || null,
      ip: req.ip || null
    });

    pool
      .promise()
      .query(
        'CALL UpsertSessionWithRefresh(?, ?, ?, ?, ?, ?)',
        [
          sessionId,
          req.user.userID,
          refreshExpiresAt.getTime(),
          sessionData,
          refreshTokenHash,
          refreshExpiresAt
        ]
      )
      .catch((err) => {
        console.warn('Error storing refresh token session:', err);
      });

    const isProduction = process.env.NODE_ENV === 'production';
    res.cookie('refreshToken', refreshToken, {
      httpOnly: true,
      secure: isProduction,
      sameSite: isProduction ? 'none' : 'lax',
      maxAge: refreshTokenMs
    });

    console.log('assigniing token on login: '+ token);
    const redirectUrl = `${frontendPath}/login?token=${token}`;
    res.redirect(redirectUrl);  // Redirect to the frontend with the token in the URL
  }
);

// Refresh access token
router.post('/refresh', (req, res) => {
  const refreshToken =
    req.cookies?.refreshToken ||
    req.body?.refreshToken ||
    req.headers['x-refresh-token'];

  if (!refreshToken) {
    return res.status(401).json({ message: 'No refresh token provided' });
  }

  jwt.verify(refreshToken, refreshTokenSecret, async (err, user) => {
    if (err) {
      return res.status(403).json({ message: 'Invalid or expired refresh token' });
    }

    const refreshTokenHash = crypto
      .createHash('sha256')
      .update(refreshToken)
      .digest('hex');

    try {
      const [sessionResults] = await pool
        .promise()
        .query('CALL GetSessionByRefreshHash(?)', [refreshTokenHash]);
      const sessionRow = sessionResults?.[0]?.[0];

      if (!sessionRow) {
        return res.status(403).json({ message: 'Refresh token not found or revoked' });
      }

      const newRefreshToken = jwt.sign(
        { id: user.id, email: user.email },
        refreshTokenSecret,
        { expiresIn: refreshTokenTtl }
      );

      const newRefreshTokenHash = crypto
        .createHash('sha256')
        .update(newRefreshToken)
        .digest('hex');

      const newRefreshExpiresAt = new Date(Date.now() + refreshTokenMs);

      await pool
        .promise()
        .query('CALL RotateRefreshToken(?, ?, ?)', [
          refreshTokenHash,
          newRefreshTokenHash,
          newRefreshExpiresAt
        ]);

      const isProduction = process.env.NODE_ENV === 'production';
      res.cookie('refreshToken', newRefreshToken, {
        httpOnly: true,
        secure: isProduction,
        sameSite: isProduction ? 'none' : 'lax',
        maxAge: refreshTokenMs
      });

    const newAccessToken = jwt.sign(
      { id: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: accessTokenTtl }
    );

      return res.json({ token: newAccessToken });
    } catch (dbErr) {
      console.warn('Error refreshing token:', dbErr);
      return res.status(500).json({ message: 'Failed to refresh token' });
    }
  });
});

// Failure route for Google login
router.get('/failure', (req, res) => {
  res.status(401).json({ message: 'Login failed' });
});

// Logout route
router.post('/logout', (req, res) => {
  const refreshToken =
    req.cookies?.refreshToken ||
    req.body?.refreshToken ||
    req.headers['x-refresh-token'];

  if (refreshToken) {
    const refreshTokenHash = crypto
      .createHash('sha256')
      .update(refreshToken)
      .digest('hex');

    pool
      .promise()
      .query('CALL RevokeRefreshToken(?)', [refreshTokenHash])
      .catch((err) => {
        console.warn('Error revoking refresh token:', err);
      });
  }

  res.clearCookie('refreshToken');
  console.log('logged out');
  res.status(200).json({ message: 'Logged out successfully' });
});

// Route to check if the user is authenticated using JWT (for protected routes)
router.get('/check-auth', (req, res) => {
  const token = req.headers['authorization'];
  console.log("toke: "+ token);
  if (!token) {
    return res.status(401).json({ message: 'No token provided' });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      console.log("Verify err: " + err);
      return res.status(403).json({ message: 'Invalid or expired token' });
    }

    // If the token is valid, return user info
    console.log('Checking auth: ' + user.email);
    res.json({ user });
  });
});

/*export function isAuthenticated(req){
  const token = req.headers['authorization'];
  console.log("toke: "+ token);
  if (!token) {
    return res.status(401).json({ message: 'No token provided' });
  }
}$*/

module.exports = router;
