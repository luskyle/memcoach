/**
 * WebDAV 读写（快照契约：memcoach/backup.json）。
 * 与记忆教练 App 的云盘同步共用同一份 JSON——插件收藏即被各端合并入库。
 */
const REMOTE_PATH = '/memcoach/backup.json';

async function loadConfig() {
  const cfg = await chrome.storage.local.get(['davUrl', 'davUser', 'davPass']);
  return {
    url: (cfg.davUrl || '').trim(),
    user: cfg.davUser || '',
    pass: cfg.davPass || '',
  };
}

function authHeaders(cfg) {
  const token = btoa(`${cfg.user}:${cfg.pass}`);
  return { Authorization: `Basic ${token}` };
}

async function davGet(cfg) {
  const res = await fetch(cfg.url + REMOTE_PATH, { headers: authHeaders(cfg), cache: 'no-store' });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`读取云端失败（HTTP ${res.status}）`);
  return res.json();
}

async function davPut(cfg, payload) {
  // 确保父目录存在（MKCOL，已存在时忽略错误）
  try {
    await fetch(cfg.url + '/memcoach', { method: 'MKCOL' });
  } catch (_) {}
  const res = await fetch(cfg.url + REMOTE_PATH, {
    method: 'PUT',
    headers: { ...authHeaders(cfg), 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(`写入云端失败（HTTP ${res.status}）`);
  // 通知本机记忆教练桌面端立即同步（实时效果；未运行桌面端时静默）
  pingDesktop();
}

/** 通知桌面端记忆教练有新版数据（本地 9797 端口，秒级同步用）。 */
function pingDesktop() {
  try {
    fetch('http://127.0.0.1:9797/ping', { mode: 'no-cors' }).catch(() => {});
  } catch (_) {}
}

/** 生成不冲突的 id：负整数（避开 App 正值自增）；时间戳基 + 自增保证跨会话唯一。 */
let _seq = 0;
function nextId() {
  _seq += 1;
  return -(Date.now() * 1000 + _seq);
}

function iso(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400000);
  return d.toISOString();
}

/** 简单语言判定（与 App 启发式一致：假名→ja，汉字→zh，拉丁→en）。 */
function guessLang(text) {
  if (/[\u3040-\u30ff]/.test(text)) return 'ja';
  if (/[\u3400-\u9fff]/.test(text)) return 'zh';
  if (/[a-zA-Z]/.test(text)) return 'en';
  return 'other';
}

/**
 * 追加一条收藏（未成卡条目形式，与 App 收件箱对应：status=inbox）。
 * 返回新的快照（在传入 rows 上原地追加并返回引用）。
 */
function appendInbox(snapshot, text, { url, title, note, collectionId }) {
  const rows = snapshot.rows;
  rows.items = rows.items || [];
  rows.cards = rows.cards || [];
  rows.item_collections = rows.item_collections || [];

  const now = new Date().toISOString();
  const itemId = nextId();
  const cardId = nextId();

  rows.cards.push({
    id: cardId,
    wordId: null,
    kind: 'word',
    prompt: text.slice(0, 500),
    answer: '',
    audioFile: null,
    lang: guessLang(text),
    tags: null,
    repetitions: 0,
    easeFactor: 2.5,
    intervalDays: 0,
    dueAt: iso(1), // 明天首复
    lastReviewedAt: null,
    createdAt: now,
  });
  rows.items.push({
    id: itemId,
    cardId,
    source: 'browser',
    mediaPath: null,
    originalUrl: url || null,
    sourceTitle: title || null,
    note: note || null,
    lang: guessLang(text),
    status: 'learning', // 直接入复习队列（无收件箱中转）
    createdAt: now,
  });
  if (collectionId) {
    rows.item_collections.push({ itemId, collectionId, isPrimary: true });
  }
  return snapshot;
}

/** 追加一条「已成卡」收藏（popup 直接进复习队列）。 */
function appendCard(snapshot, text, answer, { url, title, collectionId }) {
  const rows = snapshot.rows;
  rows.items = rows.items || [];
  rows.cards = rows.cards || [];
  rows.item_collections = rows.item_collections || [];

  const now = new Date().toISOString();
  const itemId = nextId();
  const cardId = nextId();

  rows.cards.push({
    id: cardId,
    wordId: null,
    kind: 'word',
    prompt: text.slice(0, 500),
    answer: answer || '（待补充答案）',
    audioFile: null,
    lang: guessLang(text),
    tags: null,
    repetitions: 0,
    easeFactor: 2.5,
    intervalDays: 0,
    dueAt: iso(1),
    lastReviewedAt: null,
    createdAt: now,
  });
  rows.items.push({
    id: itemId,
    cardId,
    source: 'browser',
    mediaPath: null,
    originalUrl: url || null,
    sourceTitle: title || null,
    note: null,
    lang: guessLang(text),
    status: 'learning',
    createdAt: now,
  });
  if (collectionId) {
    rows.item_collections.push({ itemId, collectionId, isPrimary: true });
  }
  return snapshot;
}

/** 快照中的分类列表（popup 下拉用）。失败返回 null，调用方保留现状。 */
async function fetchCollections() {
  const cfg = await loadConfig();
  if (!cfg.url) return null;
  let snap;
  try {
    snap = await davGet(cfg);
  } catch (_) {
    return null;
  }
  if (!snap || !snap.rows) return null;
  return snap.rows.collections || null;
}

// 浏览器端：popup/background 通过 <script>/importScripts 共享全局作用域调用上述函数。