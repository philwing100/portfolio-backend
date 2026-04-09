// database.js — PostgreSQL connection via pg (Supabase)

const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool(
  process.env.DATABASE_URL
    ? {
        connectionString: process.env.DATABASE_URL,
        ssl: { rejectUnauthorized: false }
      }
    : {
        host: process.env.host,
        user: process.env.user,
        password: process.env.password,
        database: process.env.name,
        port: process.env.port || 5432,
        ssl: { rejectUnauthorized: false }
      }
);

pool.connect((err, client, release) => {
  if (err) {
    console.error('Database connection error:', err.message);
    return;
  }
  release();
  console.log('Database connected!');
});

module.exports = pool;
