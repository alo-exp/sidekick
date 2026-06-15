const express = require('express');
const path = require('node:path');
const notesRouter = require('./routes/notes');

const app = express();
const PORT = Number(process.env.PORT || 3456);

app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, 'public')));

app.use('/api/notes', notesRouter);

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Test Notes App running at http://localhost:${PORT}`);
  });
}

module.exports = app;

