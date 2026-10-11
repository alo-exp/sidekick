const express = require('express');
const { getDb } = require('../db/database');

const router = express.Router();

function parseBool(value) {
  if (value === true || value === 1 || value === '1') return true;
  if (value === false || value === 0 || value === '0') return false;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true' || normalized === 'yes') return true;
    if (normalized === 'false' || normalized === 'no') return false;
  }
  return null;
}

function normalizeTags(tags) {
  if (Array.isArray(tags)) {
    return dedupeTags(tags);
  }
  if (typeof tags === 'string') {
    return dedupeTags(tags.split(','));
  }
  return [];
}

function dedupeTags(values) {
  const seen = new Set();
  const result = [];
  for (const raw of values) {
    const tag = String(raw).trim();
    if (!tag) continue;
    const key = tag.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(tag);
  }
  return result;
}

function serializeTags(tags) {
  return normalizeTags(tags).join(', ');
}

function deserializeTags(tags) {
  if (!tags) return [];
  return String(tags)
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function noteRowToApi(row) {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    tags: deserializeTags(row.tags),
    pinned: Boolean(row.pinned),
    archived: Boolean(row.archived),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function getSearchClause(query) {
  const normalized = String(query || '').trim();
  if (!normalized) {
    return null;
  }
  return {
    sql: '(title LIKE ? OR body LIKE ? OR tags LIKE ?)',
    params: Array(3).fill(`%${normalized}%`),
  };
}

router.get('/', (req, res) => {
  const db = getDb();
  const clauses = [];
  const params = [];

  const archived = parseBool(req.query.archived);
  if (archived !== null) {
    clauses.push('archived = ?');
    params.push(archived ? 1 : 0);
  }

  const pinned = parseBool(req.query.pinned);
  if (pinned !== null) {
    clauses.push('pinned = ?');
    params.push(pinned ? 1 : 0);
  }

  const searchClause = getSearchClause(req.query.query);
  if (searchClause) {
    clauses.push(searchClause.sql);
    params.push(...searchClause.params);
  }

  const tag = String(req.query.tag || '').trim();
  if (tag) {
    clauses.push('tags LIKE ?');
    params.push(`%${tag}%`);
  }

  let sql = 'SELECT * FROM notes';
  if (clauses.length > 0) {
    sql += ` WHERE ${clauses.join(' AND ')}`;
  }
  sql += ' ORDER BY pinned DESC, updated_at DESC, id DESC';

  const notes = db.prepare(sql).all(...params).map(noteRowToApi);
  res.json(notes);
});

router.delete('/archived', (req, res) => {
  const db = getDb();
  const result = db.prepare('DELETE FROM notes WHERE archived = 1').run();
  res.json({ deleted: result.changes });
});

router.get('/:id', (req, res) => {
  const db = getDb();
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1) {
    return res.status(400).json({ error: 'Invalid note ID' });
  }

  const note = db.prepare('SELECT * FROM notes WHERE id = ?').get(id);
  if (!note) {
    return res.status(404).json({ error: 'Note not found' });
  }

  res.json(noteRowToApi(note));
});

router.post('/', (req, res) => {
  const title = typeof req.body.title === 'string' ? req.body.title.trim() : '';
  const body = typeof req.body.body === 'string' ? req.body.body : '';
  const tags = serializeTags(req.body.tags);
  const pinned = parseBool(req.body.pinned);
  const archived = parseBool(req.body.archived);

  if (!title) {
    return res.status(400).json({ error: 'Title is required' });
  }

  const db = getDb();
  const result = db
    .prepare(
      'INSERT INTO notes (title, body, tags, pinned, archived) VALUES (?, ?, ?, ?, ?)',
    )
    .run(
      title,
      body,
      tags,
      pinned ? 1 : 0,
      archived ? 1 : 0,
    );

  const note = db.prepare('SELECT * FROM notes WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json(noteRowToApi(note));
});

router.put('/:id', (req, res) => {
  const db = getDb();
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1) {
    return res.status(400).json({ error: 'Invalid note ID' });
  }

  const existing = db.prepare('SELECT * FROM notes WHERE id = ?').get(id);
  if (!existing) {
    return res.status(404).json({ error: 'Note not found' });
  }

  const updates = [];
  const values = [];

  if (req.body.title !== undefined) {
    const title = typeof req.body.title === 'string' ? req.body.title.trim() : '';
    if (!title) {
      return res.status(400).json({ error: 'Title cannot be empty' });
    }
    updates.push('title = ?');
    values.push(title);
  }

  if (req.body.body !== undefined) {
    if (typeof req.body.body !== 'string') {
      return res.status(400).json({ error: 'Body must be a string' });
    }
    updates.push('body = ?');
    values.push(req.body.body);
  }

  if (req.body.tags !== undefined) {
    updates.push('tags = ?');
    values.push(serializeTags(req.body.tags));
  }

  if (req.body.pinned !== undefined) {
    const pinned = parseBool(req.body.pinned);
    if (pinned === null) {
      return res.status(400).json({ error: 'pinned must be a boolean value' });
    }
    updates.push('pinned = ?');
    values.push(pinned ? 1 : 0);
  }

  if (req.body.archived !== undefined) {
    const archived = parseBool(req.body.archived);
    if (archived === null) {
      return res.status(400).json({ error: 'archived must be a boolean value' });
    }
    updates.push('archived = ?');
    values.push(archived ? 1 : 0);
  }

  if (updates.length === 0) {
    return res.status(400).json({ error: 'No fields to update' });
  }

  updates.push("updated_at = datetime('now')");
  db.prepare(`UPDATE notes SET ${updates.join(', ')} WHERE id = ?`).run(...values, id);
  const note = db.prepare('SELECT * FROM notes WHERE id = ?').get(id);
  res.json(noteRowToApi(note));
});

router.delete('/:id', (req, res) => {
  const db = getDb();
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1) {
    return res.status(400).json({ error: 'Invalid note ID' });
  }

  const result = db.prepare('DELETE FROM notes WHERE id = ?').run(id);
  if (result.changes === 0) {
    return res.status(404).json({ error: 'Note not found' });
  }

  res.status(204).send();
});

module.exports = router;
