(function () {
  const API = '/api/notes';
  const state = {
    selectedId: null,
    search: '',
    tag: '',
    archived: '',
    sort: 'updated_desc',
    notes: [],
    selectedIds: new Set(),
  };

  const els = {
    statusPill: document.getElementById('statusPill'),
    noteList: document.getElementById('noteList'),
    searchInput: document.getElementById('searchInput'),
    tagFilter: document.getElementById('tagFilter'),
    archiveFilter: document.getElementById('archiveFilter'),
    newNoteButton: document.getElementById('newNoteButton'),
    editorHeading: document.getElementById('editorHeading'),
    editorMeta: document.getElementById('editorMeta'),
    editorForm: document.getElementById('editorForm'),
    noteTitle: document.getElementById('noteTitle'),
    noteBody: document.getElementById('noteBody'),
    noteTags: document.getElementById('noteTags'),
    notePinned: document.getElementById('notePinned'),
    noteArchived: document.getElementById('noteArchived'),
    deleteButton: document.getElementById('deleteButton'),
    exportButton: document.getElementById('exportButton'),
    importInput: document.getElementById('importInput'),
    sortSelect: document.getElementById('sortSelect'),
    bulkArchiveButton: document.getElementById('bulkArchiveButton'),
  };

  function formatTimestamp(value) {
    if (!value) return '';
    const date = new Date(`${value.replace(' ', 'T')}Z`);
    return new Intl.DateTimeFormat('en', {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }).format(date);
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function notePreview(note) {
    const parts = [note.body || ''];
    if (note.tags?.length) {
      parts.push(`Tags: ${note.tags.join(', ')}`);
    }
    return parts.join('\n').trim();
  }

  function updateStatus(message) {
    els.statusPill.textContent = message;
  }

  function currentQueryParams() {
    const params = new URLSearchParams();
    if (state.search.trim()) params.set('query', state.search.trim());
    if (state.tag) params.set('tag', state.tag);
    if (state.archived !== '') params.set('archived', state.archived);
    if (state.sort && state.sort !== 'updated_desc') params.set('sort', state.sort);
    return params;
  }

  function updateTagFilterOptions(notes) {
    const tags = new Set();
    for (const note of notes) {
      for (const tag of note.tags || []) {
        tags.add(tag);
      }
    }

    const current = els.tagFilter.value;
    const options = ['<option value="">All tags</option>']
      .concat([...tags].sort((a, b) => a.localeCompare(b)).map((tag) => {
        return `<option value="${escapeHtml(tag)}">${escapeHtml(tag)}</option>`;
      }));

    els.tagFilter.innerHTML = options.join('');
    if ([...tags].includes(current)) {
      els.tagFilter.value = current;
    } else {
      els.tagFilter.value = '';
      state.tag = '';
    }
  }

  function renderNotes() {
    if (state.notes.length === 0) {
      els.noteList.innerHTML = `
        <div class="empty-state">
          <strong>No notes match your filters yet.</strong>
          <div>Try a different search or create a new note.</div>
        </div>
      `;
      return;
    }

    els.noteList.innerHTML = state.notes.map((note) => {
      const selected = note.id === state.selectedId ? 'active' : '';
      const checked = state.selectedIds.has(note.id) ? 'checked' : '';
      const archivedChip = note.archived
        ? '<span class="chip status-chip warn">Archived</span>'
        : '<span class="chip status-chip">Active</span>';
      const pinnedChip = note.pinned ? '<span class="chip">Pinned</span>' : '';
      const tags = (note.tags || []).map((tag) => `<span class="chip">${escapeHtml(tag)}</span>`).join('');
      return `
        <article class="note-card ${selected}" data-id="${note.id}">
          <header>
            <div>
              <input type="checkbox" class="note-checkbox" data-note-id="${note.id}" ${checked} style="margin-right:8px;cursor:pointer;">
              <h3>${escapeHtml(note.title)}</h3>
              <div class="meta">${formatTimestamp(note.updated_at)}</div>
            </div>
            <div class="chips">${pinnedChip}${archivedChip}</div>
          </header>
          <div class="preview">${escapeHtml(notePreview(note) || 'No body yet.')}</div>
          <div class="chips">${tags}</div>
        </article>
      `;
    }).join('');
  }

  function renderEditor(note) {
    if (!note) {
      els.editorHeading.textContent = 'Create note';
      els.editorMeta.textContent = 'No note selected';
      els.noteTitle.value = '';
      els.noteBody.value = '';
      els.noteTags.value = '';
      els.notePinned.checked = false;
      els.noteArchived.checked = false;
      els.deleteButton.disabled = true;
      return;
    }

    els.editorHeading.textContent = `Editing note #${note.id}`;
    els.editorMeta.textContent = `Last updated ${formatTimestamp(note.updated_at)}`;
    els.noteTitle.value = note.title || '';
    els.noteBody.value = note.body || '';
    els.noteTags.value = (note.tags || []).join(', ');
    els.notePinned.checked = Boolean(note.pinned);
    els.noteArchived.checked = Boolean(note.archived);
    els.deleteButton.disabled = false;
  }

  function currentNote() {
    return state.notes.find((note) => note.id === state.selectedId) || null;
  }

  async function loadNotes() {
    const params = currentQueryParams();
    const res = await fetch(`${API}${params.toString() ? `?${params}` : ''}`);
    const notes = await res.json();
    state.notes = notes;
    if (state.selectedId && !notes.some((note) => note.id === state.selectedId)) {
      state.selectedId = null;
    }
    updateTagFilterOptions(notes);
    renderNotes();
    renderEditor(currentNote());
    updateStatus(`${notes.length} note${notes.length === 1 ? '' : 's'} loaded`);
  }

  async function saveNote(event) {
    event.preventDefault();
    const payload = {
      title: els.noteTitle.value.trim(),
      body: els.noteBody.value,
      tags: els.noteTags.value,
      pinned: els.notePinned.checked,
      archived: els.noteArchived.checked,
    };

    if (!payload.title) {
      els.noteTitle.focus();
      return;
    }

    const method = state.selectedId ? 'PUT' : 'POST';
    const url = state.selectedId ? `${API}/${state.selectedId}` : API;
    const res = await fetch(url, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      const error = await res.json().catch(() => ({}));
      updateStatus(error.error || 'Failed to save note');
      return;
    }

    const saved = await res.json();
    state.selectedId = saved.id;
    await loadNotes();
    const fresh = state.notes.find((note) => note.id === saved.id) || saved;
    renderEditor(fresh);
    updateStatus(`Saved "${saved.title}"`);
  }

  async function deleteSelectedNote() {
    if (!state.selectedId) {
      return;
    }
    const note = currentNote();
    if (!note) {
      return;
    }
    const confirmed = window.confirm(`Delete "${note.title}"? This cannot be undone.`);
    if (!confirmed) {
      return;
    }
    const res = await fetch(`${API}/${note.id}`, { method: 'DELETE' });
    if (!res.ok && res.status !== 204) {
      updateStatus('Failed to delete note');
      return;
    }
    state.selectedId = null;
    await loadNotes();
    updateStatus(`Deleted "${note.title}"`);
  }

  function selectNote(id) {
    state.selectedId = id;
    const note = currentNote();
    renderNotes();
    renderEditor(note);
    if (note) {
      updateStatus(`Selected "${note.title}"`);
    }
  }

  els.noteList.addEventListener('click', (event) => {
    const card = event.target.closest('.note-card');
    if (!card) return;
    selectNote(Number(card.dataset.id));
  });

  els.noteList.addEventListener('change', (event) => {
    const checkbox = event.target.closest('.note-checkbox');
    if (!checkbox) return;
    const noteId = Number(checkbox.dataset.noteId);
    if (checkbox.checked) {
      state.selectedIds.add(noteId);
    } else {
      state.selectedIds.delete(noteId);
    }
  });

  els.newNoteButton.addEventListener('click', () => {
    state.selectedId = null;
    renderNotes();
    renderEditor(null);
    els.noteTitle.focus();
    updateStatus('Creating a new note');
  });

  els.searchInput.addEventListener('input', async (event) => {
    state.search = event.target.value;
    await loadNotes();
  });

  els.tagFilter.addEventListener('change', async (event) => {
    state.tag = event.target.value;
    await loadNotes();
  });

  els.archiveFilter.addEventListener('change', async (event) => {
    state.archived = event.target.value;
    await loadNotes();
  });

    els.sortSelect.addEventListener('change', () => {
      state.sort = els.sortSelect.value;
      loadNotes();
    });

  els.editorForm.addEventListener('submit', saveNote);
  els.deleteButton.addEventListener('click', deleteSelectedNote);
  
  function isTyping() {
    const tag = document.activeElement?.tagName?.toLowerCase();
    return tag === 'input' || tag === 'textarea' || tag === 'select';
  }
  
  document.addEventListener('keydown', (event) => {
    if (event.ctrlKey && event.key === 'Enter') {
      if (isTyping()) {
        event.preventDefault();
        els.editorForm.requestSubmit();
      }
      return;
    }
    
    if (event.key === 'Escape') {
      if (state.selectedId !== null) {
        state.selectedId = null;
        renderNotes();
        renderEditor(null);
        updateStatus('Creating a new note');
      } else if (isTyping()) {
        document.activeElement.blur();
      }
      return;
    }
    
    if (isTyping()) return;
    
    if (event.key === 'n' || event.key === 'N') {
      event.preventDefault();
      state.selectedId = null;
      renderNotes();
      renderEditor(null);
      els.noteTitle.focus();
      updateStatus('Creating a new note');
      return;
    }
    
    if (event.key === '/') {
      event.preventDefault();
      els.searchInput.focus();
      return;
    }
  });

  async function exportNotes() {
    updateStatus('Exporting notes…');
    try {
      const res = await fetch(`${API}/export`);
      const notes = await res.json();
      const blob = new Blob([JSON.stringify(notes, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'notes-export.json';
      a.click();
      URL.revokeObjectURL(url);
      updateStatus(`Exported ${notes.length} note${notes.length === 1 ? '' : 's'}`);
    } catch (error) {
      console.error(error);
      updateStatus('Export failed');
    }
  }

  async function importNotes(file) {
    updateStatus('Importing notes…');
    try {
      const text = await file.text();
      const notes = JSON.parse(text);
      const res = await fetch(`${API}/import`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(notes),
      });
      if (!res.ok) {
        const error = await res.json().catch(() => ({}));
        updateStatus(error.error || 'Import failed');
        return;
      }
      const result = await res.json();
      await loadNotes();
      updateStatus(`Imported ${result.imported} note${result.imported === 1 ? '' : 's'}`);
    } catch (error) {
      console.error(error);
      updateStatus('Import failed');
    }
  }

  els.exportButton.addEventListener('click', exportNotes);
  els.importInput.addEventListener('change', (event) => {
    const file = event.target.files[0];
    if (file) importNotes(file);
    event.target.value = '';
  });

  async function bulkArchiveSelected() {
    if (state.selectedIds.size === 0) {
      updateStatus('No notes selected to archive');
      return;
    }
    updateStatus('Archiving selected notes…');
    try {
      const ids = [...state.selectedIds];
      const res = await fetch(`${API}/bulk-archive`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids }),
      });
      if (!res.ok) {
        const error = await res.json().catch(() => ({}));
        updateStatus(error.error || 'Bulk archive failed');
        return;
      }
      const result = await res.json();
      state.selectedIds.clear();
      await loadNotes();
      updateStatus(`Archived ${result.archived} note${result.archived === 1 ? '' : 's'}`);
    } catch (error) {
      console.error(error);
      updateStatus('Bulk archive failed');
    }
  }

  els.bulkArchiveButton.addEventListener('click', bulkArchiveSelected);

  loadNotes().catch((error) => {
    console.error(error);
    updateStatus('Failed to load notes');
  });
})();
