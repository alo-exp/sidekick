const fs = require('node:fs');
const path = require('node:path');
const Database = require('better-sqlite3');

let db;

function defaultDatabasePath() {
  return process.env.NOTES_APP_DB_PATH || path.join(process.cwd(), 'data', 'notes.db');
}

function getDb() {
  if (!db) {
    const dbPath = defaultDatabasePath();
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    db = new Database(dbPath);
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
    initSchema(db);
  }
  return db;
}

function initSchema(database) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      tags TEXT NOT NULL DEFAULT '',
      pinned INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_notes_pinned ON notes(pinned DESC);
    CREATE INDEX IF NOT EXISTS idx_notes_archived ON notes(archived);
  `);
}

function resetDb() {
  if (db) {
    db.close();
    db = null;
  }
}

module.exports = {
  getDb,
  resetDb,
  defaultDatabasePath,
};

