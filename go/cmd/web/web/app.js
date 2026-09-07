/* Uniclient web UI — vanilla JS, no dependencies, talks to the local engine. */
'use strict';

/* ── Platform metadata ──────────────────────────────────────────── */

const PLATFORMS = {
  telegram:  { name: 'Telegram',   color: '#2AABEE' },
  github:    { name: 'GitHub',     color: '#6e7681' },
  irc:       { name: 'IRC',        color: '#21b26c' },
  matrix:    { name: 'Matrix',     color: '#0DBD8B' },
  xmpp:      { name: 'XMPP',       color: '#e8871e' },
  deltachat: { name: 'Delta Chat', color: '#1fb6ca' },
  bale:      { name: 'Bale',       color: '#3b6fd4' },
  rubika:    { name: 'Rubika',     color: '#e04658' },
  teamspeak: { name: 'TeamSpeak',  color: '#4a5c7f' },
  mumble:    { name: 'Mumble',     color: '#5a7d9a' },
};

const MSG_STATUS = { 1: 'sending', 2: 'sent', 3: 'delivered', 4: 'read', 5: 'failed' };

/* ── State ──────────────────────────────────────────────────────── */

let accounts = [];          // AccountInfo[]
let chats = [];             // ChatInfo[] (unified)
let current = null;         // { accountId, chatId, title, type }
let messages = [];          // CachedMessage[] for current chat (newest-first)
let authFlow = null;        // { accountId } while a login modal is open
let accountFilter = null;   // accountID to filter the chat list by
let ws = null;
let wsBackoff = 1000;

/* ── API helper ─────────────────────────────────────────────────── */

async function api(path, opts = {}) {
  const init = { method: opts.method || 'GET', headers: {} };
  if (opts.body !== undefined) {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(opts.body);
  }
  const res = await fetch(path, init);
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { /* non-JSON */ }
  if (!res.ok) throw new Error((data && data.error) || (res.status + ' ' + res.statusText));
  return data;
}

/* ── Boot ───────────────────────────────────────────────────────── */

async function boot() {
  bindUI();
  try { await refreshAccounts(); } catch (e) { toast(e.message); }
  try { await refreshChats(); } catch (e) { toast(e.message); }
  connectWS();
}

function bindUI() {
  document.getElementById('addAccountBtn').addEventListener('click', showAddAccount);
  document.getElementById('newChatBtn').addEventListener('click', showNewChat);
  document.getElementById('refreshBtn').addEventListener('click', async () => {
    await refreshChats().catch(e => toast(e.message));
    if (current) await loadMessages().catch(e => toast(e.message));
  });

  const input = document.getElementById('composerInput');
  const send = document.getElementById('sendBtn');
  send.addEventListener('click', sendMessage);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });
  input.addEventListener('input', autoGrow);
}

function autoGrow() {
  const el = document.getElementById('composerInput');
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 160) + 'px';
}

/* ── Accounts rail ──────────────────────────────────────────────── */

async function refreshAccounts() {
  accounts = (await api('/api/accounts')) || [];
  renderAccounts();
}

function renderAccounts() {
  const rail = document.getElementById('accountRail');
  rail.innerHTML = '';
  for (const a of accounts) {
    const meta = PLATFORMS[a.platform] || { name: a.platform, color: '#5d6679' };
    const chip = document.createElement('div');
    chip.className = 'account-chip';
    chip.style.background = meta.color;
    chip.textContent = (a.display_name || meta.name).trim().charAt(0).toUpperCase() || '?';
    chip.title = (a.display_name || meta.name) + ' · ' + meta.name;

    const dot = document.createElement('span');
    dot.className = 'dot' + (a.conn_state === 2 ? ' connected' : a.conn_state === 1 ? ' connecting' : '');
    chip.appendChild(dot);

    chip.addEventListener('click', () => showAccountModal(a.id));
    rail.appendChild(chip);
  }
}

function showAccountModal(accountId) {
  const a = accounts.find(x => x.id === accountId);
  if (!a) return;
  const meta = PLATFORMS[a.platform] || { name: a.platform, color: '#5d6679' };
  const stateLabel = ['offline', 'connecting', 'online', 'unstable', 'auth needed'][a.conn_state] || 'offline';

  openModal(`
    <h2>${esc(a.display_name || meta.name)}</h2>
    <div class="modal-sub">${esc(meta.name)} · ${stateLabel} · <code>${esc(a.id)}</code></div>
    <button class="btn" id="mConnect">Connect</button>
    <button class="btn secondary" id="mDisconnect">Disconnect</button>
    <button class="btn secondary" id="mRemove">Remove account</button>
    <button class="btn secondary" id="mClose">Close</button>
  `);

  document.getElementById('mConnect').onclick = async () => {
    try { await api(`/api/accounts/${encodeURIComponent(a.id)}/connect`, { method: 'POST' }); closeModal(); }
    catch (e) { toast(e.message); }
  };
  document.getElementById('mDisconnect').onclick = async () => {
    try { await api(`/api/accounts/${encodeURIComponent(a.id)}/disconnect`, { method: 'POST' }); closeModal(); }
    catch (e) { toast(e.message); }
  };
  document.getElementById('mRemove').onclick = async () => {
    if (!confirm(`Remove the ${meta.name} account "${a.display_name || a.id}"? Stored credentials are deleted.`)) return;
    try { await api(`/api/accounts/${encodeURIComponent(a.id)}`, { method: 'DELETE' }); closeModal(); await refreshAccounts(); await refreshChats(); }
    catch (e) { toast(e.message); }
  };
  document.getElementById('mClose').onclick = closeModal;
}

/* ── Add account / auth flow ────────────────────────────────────── */

function showAddAccount() {
  const buttons = Object.entries(PLATFORMS)
    .map(([id, m]) => `
      <button class="platform-btn" data-platform="${id}">
        <span class="pglyph" style="background:${m.color}">${m.name.charAt(0)}</span>${esc(m.name)}
      </button>`)
    .join('');
  openModal(`
    <h2>Add an account</h2>
    <div class="modal-sub">Pick a platform to log in. Telegram, GitHub and IRC are the most tested.</div>
    <div class="platform-grid">${buttons}</div>
  `);
  document.querySelectorAll('.platform-btn').forEach(btn => {
    btn.addEventListener('click', () => createAccount(btn.dataset.platform));
  });
}

async function createAccount(platform) {
  try {
    const res = await api('/api/accounts', { method: 'POST', body: { platform } });
    authFlow = { accountId: res.account_id };
    await refreshAccounts();
    const state = await api(`/api/accounts/${encodeURIComponent(res.account_id)}/auth/start`, { method: 'POST' });
    renderAuthState(state);
  } catch (e) {
    toast(e.message);
  }
}

/* renderAuthState draws the current login step and wires the next action. */
function renderAuthState(state) {
  if (!state || !authFlow) return;
  const id = authFlow.accountId;
  const meta = PLATFORMS[state.platform] || { name: state.platform };

  let body = `<h2>${esc(meta.name)} login</h2><div class="modal-sub">Step: ${esc(state.state)}</div>`;

  if (state.state === 'ready') {
    body += `
      <div class="ready-wrap">
        <div class="check">&#10003;</div>
        <div class="who">${esc(state.display_name || 'Logged in')}</div>
        <div class="platform">${esc(meta.name)} account connected</div>
      </div>
      <button class="btn" id="authDone">Done</button>`;
    openModal(body);
    document.getElementById('authDone').onclick = async () => {
      authFlow = null;
      closeModal();
      await refreshAccounts().catch(() => {});
      await refreshChats().catch(() => {});
    };
    return;
  }

  if (state.state === 'error') {
    body += `
      <div class="auth-error">${esc(state.message || state.error || 'Login failed')}</div>
      <button class="btn" id="authRetry">Try again</button>
      <button class="btn secondary" id="authCancel">Cancel</button>`;
    openModal(body);
    document.getElementById('authRetry').onclick = async () => {
      try { renderAuthState(await api(`/api/accounts/${encodeURIComponent(id)}/auth/start`, { method: 'POST' })); }
      catch (e) { toast(e.message); }
    };
    document.getElementById('authCancel').onclick = () => cancelAuth(id);
    return;
  }

  if (state.state === 'choose') {
    body += (state.options || []).map(o =>
      `<button class="choice-btn" data-option="${esc(o.id)}">${esc(o.label)}</button>`).join('');
    body += `<button class="btn secondary" id="authCancel">Cancel</button>`;
    openModal(body);
    document.querySelectorAll('.choice-btn').forEach(btn => {
      btn.addEventListener('click', () => submitAuth(id, btn.dataset.option));
    });
    document.getElementById('authCancel').onclick = () => cancelAuth(id);
    return;
  }

  if (state.state === 'qr') {
    body += `
      <div class="qr-wrap">
        <img id="qrImg" alt="Login QR code">
        <div class="qr-note">Open Telegram on your phone → Settings → Devices → Link Desktop Device, then scan this code. The code refreshes automatically.</div>
      </div>
      <button class="btn secondary" id="authCancel">Cancel</button>`;
    openModal(body);
    // Go marshals []byte as base64 — decode to the tg:// login URL.
    loadQRImage(state.qr_data ? atob(state.qr_data) : '');
    document.getElementById('authCancel').onclick = () => cancelAuth(id);
    return;
  }

  // input / otp / 2fa / email / signup — a labeled text field.
  const secret = ['token', 'password', 'code', '2fa'].includes(state.field_type) ||
                 state.state === 'otp' || state.state === '2fa';
  const inputType = secret ? 'password' : 'text';
  let info = '';
  if (state.state === 'otp') {
    info = `<div class="auth-info">A login code was sent${state.sent_to ? ' to ' + esc(state.sent_to) : ''}.` +
      (state.code_by_telegram ? ' Check your Telegram app.' : '') +
      (state.email_pattern_setup ? ' Check ' + esc(state.email_pattern_setup) + '.' : '') + '</div>';
  }
  if (state.email || state.email_pattern_login) {
    info += `<div class="auth-info">${state.email ? 'Account email: ' + esc(state.email) : ''}` +
      (state.email_pattern_login ? ' Login email: ' + esc(state.email_pattern_login) : '') + '</div>';
  }
  body += `
    ${state.error ? `<div class="auth-error">${esc(state.error)}</div>` : ''}
    ${info}
    <div class="auth-label">${esc(state.label || 'Enter details')}</div>
    ${state.hint ? `<div class="auth-hint">${esc(state.hint)}</div>` : ''}
    <input class="field" id="authField" type="${inputType}" autocomplete="off"
           placeholder="${esc(state.hint || '')}" ${state.state === 'otp' ? 'inputmode="numeric"' : ''}>
    <button class="btn" id="authNext">Continue</button>
    <button class="btn secondary" id="authBack">Back</button>
    <button class="btn secondary" id="authCancel">Cancel</button>`;
  openModal(body);

  const field = document.getElementById('authField');
  field.focus();
  const go = () => { if (field.value.trim()) submitAuth(id, field.value.trim()); };
  document.getElementById('authNext').onclick = go;
  field.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); go(); } });
  document.getElementById('authBack').onclick = async () => {
    try {
      const prev = await api(`/api/accounts/${encodeURIComponent(id)}/auth/back`, { method: 'POST' });
      if (prev) renderAuthState(prev);
    } catch (e) { toast(e.message); }
  };
  document.getElementById('authCancel').onclick = () => cancelAuth(id);
}

async function submitAuth(accountId, input) {
  try {
    const state = await api(`/api/accounts/${encodeURIComponent(accountId)}/auth/input`, { method: 'POST', body: { input } });
    renderAuthState(state);
  } catch (e) {
    toast(e.message);
  }
}

async function cancelAuth(accountId) {
  try { await api(`/api/accounts/${encodeURIComponent(accountId)}/auth/cancel`, { method: 'POST' }); } catch (_) {}
  authFlow = null;
  closeModal();
}

async function loadQRImage(text) {
  const img = document.getElementById('qrImg');
  if (!img || !text) return;
  try {
    const res = await fetch('/api/qr', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    });
    if (!res.ok) throw new Error('qr failed');
    const blob = await res.blob();
    img.src = URL.createObjectURL(blob);
  } catch (_) {
    img.outerHTML = `<div class="qr-note">Show this code in Telegram:<br><code>${esc(text)}</code></div>`;
  }
}

/* ── New chat / join channel ────────────────────────────────────── */

const ADDRESS_HINTS = {
  irc: '#channel (join) or nick (direct message)',
  github: 'dm:username, repo:owner/name, or issue:owner/repo#123',
  telegram: 'username or @username',
  matrix: '#room:server or @user:server',
  xmpp: 'user@server',
  deltachat: 'user@example.com',
  bale: 'username or phone',
  rubika: 'channel or username',
  teamspeak: 'channel',
  mumble: 'channel ID',
};

function showNewChat() {
  const connected = accounts.filter(a => a.conn_state === 2);
  if (!connected.length) {
    toast('No connected accounts — add or connect an account first.');
    return;
  }
  const options = connected.map(a => {
    const meta = PLATFORMS[a.platform] || { name: a.platform };
    const label = (a.display_name || meta.name) + ' · ' + meta.name;
    return `<option value="${esc(a.id)}" ${current && current.accountId === a.id ? 'selected' : ''}>${esc(label)}</option>`;
  }).join('');

  openModal(`
    <h2>New chat</h2>
    <div class="modal-sub">Join a channel or open a conversation by address.</div>
    <div class="auth-label">Account</div>
    <select class="field" id="ncAccount">${options}</select>
    <div class="auth-label">Address</div>
    <div class="auth-hint" id="ncHint"></div>
    <input class="field" id="ncAddress" placeholder="…" autocomplete="off">
    <button class="btn" id="ncJoin">Join channel</button>
    <button class="btn secondary" id="ncOpen">Open as conversation</button>
    <button class="btn secondary" id="ncClose">Close</button>
  `);

  const accountSel = document.getElementById('ncAccount');
  const hint = document.getElementById('ncHint');
  const updateHint = () => {
    const acc = accounts.find(a => a.id === accountSel.value);
    hint.textContent = 'Examples: ' + (ADDRESS_HINTS[acc?.platform] || 'platform-specific address');
  };
  accountSel.addEventListener('change', updateHint);
  updateHint();

  document.getElementById('ncJoin').onclick = async () => {
    const name = document.getElementById('ncAddress').value.trim();
    if (!name) return;
    try {
      await api('/api/chats/join', { method: 'POST', body: { account_id: accountSel.value, name } });
      closeModal();
      toast('Joining ' + name + '…');
      // The engine re-syncs a few seconds after the join lands; the
      // chat_snapshot event also refreshes the list automatically.
      setTimeout(() => refreshChats().catch(() => {}), 5000);
    } catch (e) { toast(e.message); }
  };

  document.getElementById('ncOpen').onclick = async () => {
    const name = document.getElementById('ncAddress').value.trim();
    if (!name) return;
    const acc = accounts.find(a => a.id === accountSel.value);
    closeModal();
    openChat({
      account_id: accountSel.value,
      chat_id: name,
      title: name,
      type: name.startsWith('#') || name.startsWith('repo:') ? 2 : 1,
      _platform: acc?.platform,
    });
  };

  document.getElementById('ncClose').onclick = closeModal;
  document.getElementById('ncAddress').focus();
}

/* ── Chat list ──────────────────────────────────────────────────── */

async function refreshChats() {
  chats = (await api('/api/chats?limit=200')) || [];
  renderChats();
}

function visibleChats() {
  if (!accountFilter) return chats;
  return chats.filter(c => c.account_id === accountFilter);
}

function renderChats() {
  const list = document.getElementById('chatList');
  list.innerHTML = '';
  const items = visibleChats();

  if (!items.length) {
    const accountById = new Map(accounts.map(a => [a.id, a]));
    const anyOnline = accounts.some(a => a.conn_state === 2);
    const div = document.createElement('div');
    div.className = 'empty';
    div.textContent = !accounts.length ? 'No accounts — add one with +'
      : !anyOnline ? 'Accounts are offline — click an account to connect'
      : 'No chats yet — they appear as accounts sync';
    list.appendChild(div);
    return;
  }

  for (const chat of items) {
    const el = document.createElement('div');
    el.className = 'chat-item' + (current && current.accountId === chat.account_id && current.chatId === chat.chat_id ? ' active' : '');
    el.dataset.account = chat.account_id;
    el.dataset.chat = chat.chat_id;

    const av = document.createElement('div');
    av.className = 'avatar';
    const platform = accounts.find(a => a.id === chat.account_id)?.platform;
    av.style.background = (PLATFORMS[platform] || {}).color || '#5d6679';
    av.textContent = initialsOf(chat.title);
    el.appendChild(av);

    const bodyEl = document.createElement('div');
    bodyEl.className = 'body';
    const top = document.createElement('div');
    top.className = 'top';
    const title = document.createElement('div');
    title.className = 'title';
    title.textContent = chat.title || chat.chat_id;
    top.appendChild(title);
    const time = document.createElement('div');
    time.className = 'time';
    time.textContent = fmtChatTime(chat.last_msg_time);
    top.appendChild(time);
    bodyEl.appendChild(top);

    const bottom = document.createElement('div');
    bottom.className = 'bottom';
    const preview = document.createElement('div');
    preview.className = 'preview';
    const prefix = chat.last_msg_is_outgoing ? 'You: '
      : (chat.last_msg_sender && chat.type !== 1 && chat.last_msg_sender ? chat.last_msg_sender.split('\n')[0] + ': ' : '');
    preview.textContent = prefix + (chat.last_msg_text || '—');
    bottom.appendChild(preview);
    if (chat.unread_count > 0) {
      const badge = document.createElement('div');
      badge.className = 'badge';
      badge.textContent = chat.unread_count > 999 ? '999+' : String(chat.unread_count);
      bottom.appendChild(badge);
    }
    bodyEl.appendChild(bottom);
    el.appendChild(bodyEl);

    el.addEventListener('click', () => openChat(chat));
    list.appendChild(el);
  }
}

/* ── Conversation view ──────────────────────────────────────────── */

async function openChat(chat) {
  current = { accountId: chat.account_id, chatId: chat.chat_id, title: chat.title || chat.chat_id, type: chat.type };
  messages = [];

  const header = document.getElementById('chatHeaderText');
  const platform = accounts.find(a => a.id === chat.account_id)?.platform;
  const meta = PLATFORMS[platform] || { name: platform };
  header.innerHTML = `${esc(current.title)}<span class="sub">${esc(meta.name)} · ${esc(chat.chat_id)}</span>`;

  const msgArea = document.getElementById('messages');
  msgArea.classList.remove('empty-main');
  msgArea.innerHTML = '<div class="empty">Loading messages…</div>';

  document.getElementById('composerInput').disabled = false;
  document.getElementById('sendBtn').disabled = false;

  renderChats(); // active highlight
  await loadMessages();
}

async function loadMessages() {
  if (!current) return;
  try {
    const msgs = await api(`/api/messages?account=${encodeURIComponent(current.accountId)}&chat=${encodeURIComponent(current.chatId)}&limit=80`);
    messages = msgs || [];
    renderMessages();
    markRead();
  } catch (e) {
    toast(e.message);
  }
}

function markRead() {
  if (!current || !messages.length) return;
  const newest = messages[messages.length - 1];
  api('/api/chats/read', {
    method: 'POST',
    body: { account_id: current.accountId, chat_id: current.chatId, up_to_msg_id: newest.msg_id || '' },
  }).then(() => refreshChats()).catch(() => {});
}

function renderMessages() {
  const area = document.getElementById('messages');
  area.innerHTML = '';
  if (!messages.length) {
    area.innerHTML = '<div class="empty">No messages yet — say hello below.</div>';
    return;
  }

  // Messages arrive newest-first; render oldest → newest.
  const ordered = [...messages].reverse();
  let lastDay = '';
  let lastSender = null;

  for (const m of ordered) {
    const day = dayKey(m.timestamp);
    if (day !== lastDay) {
      lastDay = day;
      lastSender = null;
      const div = document.createElement('div');
      div.className = 'day-divider';
      div.textContent = dayLabel(m.timestamp);
      area.appendChild(div);
    }

    if (m.is_service) {
      const div = document.createElement('div');
      div.className = 'bubble service';
      div.textContent = m.content_text || '';
      area.appendChild(div);
      continue;
    }

    const wrap = document.createElement('div');
    wrap.className = 'msg ' + (m.is_outgoing ? 'out' : 'in');
    wrap.dataset.msgId = m.msg_id;

    const bubble = document.createElement('div');
    bubble.className = 'bubble';

    const showSender = !m.is_outgoing && m.sender_name && current && current.type !== 1 &&
                       m.sender_name !== lastSender;
    if (showSender) {
      const s = document.createElement('span');
      s.className = 'sender';
      s.textContent = m.sender_name;
      bubble.appendChild(s);
    }
    if (m.forward_from) {
      const f = document.createElement('span');
      f.className = 'sender';
      f.style.color = 'var(--yellow)';
      f.textContent = '↪ ' + m.forward_from;
      bubble.appendChild(f);
    }
    if (m.reply_preview) {
      const q = document.createElement('div');
      q.className = 'reply-quote';
      q.textContent = m.reply_preview;
      bubble.appendChild(q);
    }
    if (m.has_media && (m.media_file_name || m.media_mime_type)) {
      bubble.appendChild(mediaChip(m));
    }
    const text = document.createElement('span');
    text.innerHTML = linkify(m.content_text || '');
    bubble.appendChild(text);

    const meta = document.createElement('div');
    meta.className = 'meta';
    const tm = document.createElement('span');
    tm.textContent = fmtTime(m.timestamp);
    meta.appendChild(tm);
    if (m.is_outgoing) {
      const st = document.createElement('span');
      st.className = 'status ' + (MSG_STATUS[m.status] || 'sending');
      meta.appendChild(st);
    }
    if (m.edited_at) {
      const ed = document.createElement('span');
      ed.textContent = 'edited';
      meta.appendChild(ed);
    }
    bubble.appendChild(meta);

    wrap.appendChild(bubble);
    area.appendChild(wrap);
    lastSender = m.sender_name || null;
  }

  area.scrollTop = area.scrollHeight;
}

function mediaChip(m) {
  const chip = document.createElement('div');
  chip.className = 'media-chip';
  const icon = (m.media_mime_type || '').startsWith('image/') ? '🖼' :
               (m.media_mime_type || '').startsWith('video/') ? '🎬' :
               (m.media_mime_type || '').startsWith('audio/') ? '🎵' : '📎';
  const iconEl = document.createElement('span');
  iconEl.className = 'icon';
  iconEl.textContent = icon;
  chip.appendChild(iconEl);
  const name = document.createElement('span');
  name.className = 'name';
  name.textContent = m.media_file_name || 'attachment';
  chip.appendChild(name);
  if (m.media_file_size) {
    const size = document.createElement('span');
    size.className = 'size';
    size.textContent = fmtSize(m.media_file_size);
    chip.appendChild(size);
  }
  return chip;
}

async function sendMessage() {
  const input = document.getElementById('composerInput');
  const text = input.value.trim();
  if (!text || !current) return;
  input.value = '';
  autoGrow();
  try {
    await api('/api/messages/send', {
      method: 'POST',
      body: { account_id: current.accountId, chat_id: current.chatId, text },
    });
    // The optimistic message arrives via the msg_received WS event.
  } catch (e) {
    input.value = text;
    toast(e.message);
  }
}

/* ── WebSocket events ───────────────────────────────────────────── */

function connectWS() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onmessage = (ev) => {
    let event;
    try { event = JSON.parse(ev.data); } catch (_) { return; }
    handleEvent(event);
  };
  ws.onclose = () => {
    setTimeout(connectWS, wsBackoff);
    wsBackoff = Math.min(wsBackoff * 2, 15000);
  };
  ws.onopen = () => { wsBackoff = 1000; };
}

function handleEvent(event) {
  const { type, account_id: accountId, data } = event;
  if (!data) return;

  switch (type) {
    case 'account_list':
      refreshAccounts().catch(() => {});
      break;

    case 'conn_state':
      patchAccount(accountId, a => { a.conn_state = ['disconnected', 'connecting', 'connected', 'unstable', 'auth_required'].indexOf(data.state); });
      if (data.state === 'connected') refreshChats().catch(() => {});
      break;

    case 'auth_state':
      // The event is a summary; fetch the full flow state.
      if (authFlow && authFlow.accountId === accountId) {
        api(`/api/accounts/${encodeURIComponent(accountId)}/auth`)
          .then(state => { if (state) renderAuthState(state); })
          .catch(() => {});
      }
      break;

    case 'login_code':
      if (authFlow && data.code) {
        const field = document.getElementById('authField');
        if (field) {
          field.value = data.code;
          document.getElementById('authNext')?.click();
        }
      }
      break;

    case 'chat_snapshot':
      refreshChats().catch(() => {});
      break;

    case 'chat_updated': {
      const chat = data.chat;
      if (!chat) break;
      const idx = chats.findIndex(c => c.account_id === chat.account_id && c.chat_id === chat.chat_id);
      if (idx >= 0) chats[idx] = chat; else chats.unshift(chat);
      renderChats();
      if (current && current.accountId === chat.account_id && current.chatId === chat.chat_id) {
        document.getElementById('chatHeaderText').innerHTML =
          `${esc(chat.title || chat.chat_id)}<span class="sub">${esc(subLabel(chat))}</span>`;
      }
      break;
    }

    case 'chat_removed':
      chats = chats.filter(c => !(c.account_id === accountId && c.chat_id === data.chat_id));
      renderChats();
      break;

    case 'msg_received': {
      const m = data.message;
      if (!m) break;
      if (current && current.accountId === data.account_id && current.chatId === data.chat_id) {
        upsertMessage(m);
        renderMessages();
        markRead();
      }
      refreshChats().catch(() => {});
      break;
    }

    case 'msg_status': {
      if (current && current.accountId === data.account_id && current.chatId === data.chat_id) {
        const target = messages.find(m => m.msg_id === data.msg_id || (data.local_id && m.msg_id === data.local_id) || (m.local_id && m.local_id === data.local_id));
        if (target) {
          target.status = data.status;
          if (data.msg_id && target.msg_id === (data.local_id || data.msg_id)) target.msg_id = data.msg_id;
          renderMessages();
        }
      }
      break;
    }

    case 'msg_edited': {
      if (current && current.accountId === data.account_id && current.chatId === data.chat_id) {
        const target = messages.find(m => m.msg_id === data.msg_id);
        if (target) { target.content_text = data.new_text; target.edited_at = data.edited_at; renderMessages(); }
      }
      break;
    }

    case 'msg_deleted': {
      if (current && current.accountId === data.account_id && current.chatId === data.chat_id) {
        messages = messages.filter(m => m.msg_id !== data.msg_id);
        renderMessages();
      }
      break;
    }
  }
}

function upsertMessage(m) {
  const idx = messages.findIndex(x => x.msg_id === m.msg_id || (m.local_id && x.msg_id === m.local_id));
  if (idx >= 0) messages[idx] = m;
  else messages.push(m);
}

function patchAccount(accountId, fn) {
  const a = accounts.find(x => x.id === accountId);
  if (a) { fn(a); renderAccounts(); }
}

function subLabel(chat) {
  const platform = accounts.find(a => a.id === chat.account_id)?.platform;
  const meta = PLATFORMS[platform] || { name: platform };
  return `${meta.name} · ${chat.chat_id}`;
}

/* ── Modal helpers ──────────────────────────────────────────────── */

function openModal(inner) {
  document.getElementById('modalBody').innerHTML = inner;
  document.getElementById('modalOverlay').classList.remove('hidden');
}
function closeModal() {
  document.getElementById('modalOverlay').classList.add('hidden');
}
document.getElementById('modalOverlay').addEventListener('click', (e) => {
  if (e.target.id === 'modalOverlay' && !authFlow) closeModal();
});

/* ── Toasts ─────────────────────────────────────────────────────── */

function toast(msg) {
  const box = document.getElementById('toasts');
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = msg;
  box.appendChild(el);
  setTimeout(() => el.remove(), 6000);
}

/* ── Formatting helpers ─────────────────────────────────────────── */

function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function linkify(text) {
  const escaped = esc(text);
  return escaped.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>');
}

function initialsOf(title) {
  const t = String(title || '?').trim();
  const parts = t.split(/\s+/);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return t.slice(0, 2).toUpperCase();
}

function fmtTime(ms) {
  if (!ms) return '';
  return new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function fmtChatTime(ms) {
  if (!ms) return '';
  const d = new Date(ms);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return fmtTime(ms);
  if (d.getFullYear() === now.getFullYear()) return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
  return d.toLocaleDateString([], { year: '2-digit', month: 'short', day: 'numeric' });
}

function dayKey(ms) {
  return new Date(ms).toDateString();
}

function dayLabel(ms) {
  const d = new Date(ms);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return 'Today';
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (d.toDateString() === yesterday.toDateString()) return 'Yesterday';
  return d.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
}

function fmtSize(bytes) {
  if (!bytes) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0, v = bytes;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return (i ? v.toFixed(1) : v) + ' ' + units[i];
}

/* ── Go ─────────────────────────────────────────────────────────── */

boot();
