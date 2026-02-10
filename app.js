const express = require('express');
const path = require('path');
const passport = require('passport');
const bodyParser = require('body-parser');
const cookieParser = require('cookie-parser');
const cors = require('cors');
const pool = require('./databaseConnection/database'); // Database pool connection
const jwt = require('jsonwebtoken'); // Required for JWT verification
require('dotenv').config();

const app = express();
const port = process.env.FRONTENDPORT || 3000;
const frontendPath = port == 3000 ? "http://localhost:8080" : "https://phillip-ring.vercel.app";

// Middleware to parse JSON and URL-encoded data
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(cookieParser());

// Enable CORS with credentials to allow cookie usage across origins
app.use(cors({
  origin: frontendPath, // Your frontend origin
  credentials: true, // Allow cookies and credentials to be shared
}));

// Initialize Passport for authentication
app.use(passport.initialize());

const authenticateJWT = (req, res, next) => {
  console.log('testing');
  const token = req.headers['authorization'];
  
  if (!token) {
    return res.status(401).json({ message: 'No token provided' });
  }

  // Verify the token
  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      console.log(err);
      return res.status(403).json({ message: 'Invalid or expired token' });
    }

    // Attach the decoded user to the request
    req.user = user;
    next(); // Proceed to the next middleware or route handler
  });
};

// Routes that should not require authentication (e.g., login, logout)
const authRoutes = ['/logout', '/auth'];

// Apply JWT Authentication to all /api routes, except the ones defined in authRoutes
app.use('/api', (req, res, next) => {
  if (authRoutes.some(route => req.path.startsWith(route))) {
    return next(); // Skip JWT authentication for auth routes
  } else {
    // Apply JWT authentication to all other /api routes
    return authenticateJWT(req, res, next);
  }
});

// Import and use routes (assuming routes are in 'routes/index.js')
const routes = require('./routes/index');
app.use('/api', routes); // Apply authenticateJWT middleware globally to /api routes

// Start server
if (port == 3000) {
  app.listen(port, () => {
    console.log(`Server is running on port ${port}`);
  });
} else {
  module.exports = app;
}
