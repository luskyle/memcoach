/**
 * Service Worker（简洁版）：
 * - 右键「收藏到记忆教练」→ 子菜单：选分类后收藏… / 收藏当前网页 / 各分类直达
 * - 菜单上下文：selection（划词）与 page（网页）分别提供对应入口
 * - 菜单在 SW 启动 / 扩展安装更新 / 弹窗打开时重建；
 *   分类列表来自云端快照（popup 刷新后生效）
 * - 写入 WebDAV 后 ping 桌面端 → 即时同步
 */
importScripts('snapshot.js');

// SW 每次被唤醒（点图标/消息/启动）都重建右键菜单：
// 解压扩展的「刷新」不触发 onInstalled，只有运行期执行 create 才生效。
rebuildMenus();

chrome.runtime.onInstalled.addListener(() => rebuildMenus());
chrome.runtime.onStartup.addListener(() => rebuildMenus());
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.rebuildMenus) {
    rebuildMenus().then(sendResponse);
    return true;
  }
});

/** 重建完整菜单（整树）：此刻菜单未在显示中，removeAll 安全。 */
async function rebuildMenus() {
  chrome.contextMenus.removeAll(() => {
    // 根菜单：划词与网页上下文都出现
    chrome.contextMenus.create({
      id: 'memcoach-root',
      title: '收藏到记忆教练',
      contexts: ['selection', 'page'],
    });
    // 划词 → 弹窗选分类收藏（带选区文本）
    chrome.contextMenus.create({
      id: 'memcoach-with-cat',
      parentId: 'memcoach-root',
      title: '选分类后收藏…',
      contexts: ['selection'],
    });
    chrome.contextMenus.create({
      parentId: 'memcoach-root',
      type: 'separator',
      contexts: ['selection', 'page'],
    });
    // 云端分类直达：划词收藏到分类 / 网页收藏到分类 两组
    (async () => {
      let cols = await fetchCollections();
      if (cols == null) cols = [];
      for (const c of cols) {
        try {
          chrome.contextMenus.create({
            id: `col-${c.id}`,
            parentId: 'memcoach-root',
            title: `划词收藏到「${c.name}」`,
            contexts: ['selection'],
          });
          chrome.contextMenus.create({
            id: `page-col-${c.id}`,
            parentId: 'memcoach-root',
            title: `网页收藏到「${c.name}」`,
            contexts: ['page'],
          });
        } catch (_) {}
      }
    })();
  });
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const url = tab?.url || '';
  const title = tab?.title || '';

  // ---- 网页收藏（无划词文本；prompt 存页面标题，answer 存 URL）----
  if (typeof info.menuItemId === 'string' &&
      info.menuItemId.startsWith('page-col-')) {
    const collectionId = parseInt(info.menuItemId.slice('page-col-'.length), 10) || null;
    const ok = await savePageWith(url, title, collectionId);
    notify(ok ? '已收藏当前网页' : '收藏失败：请先在弹窗配置 WebDAV');
    return;
  }

  // ---- 划词收藏 ----
  const text = (info.selectionText || '').trim();
  if (!text) return;

  if (info.menuItemId === 'memcoach-with-cat') {
    // openPopup 必须在用户手势同步上下文：storage.set 不 await
    chrome.storage.local.set({
      pendingText: text,
      pendingUrl: url,
      pendingTitle: title,
    });
    chrome.action.openPopup();
    return;
  }
  if (typeof info.menuItemId === 'string' && info.menuItemId.startsWith('col-')) {
    const collectionId = parseInt(info.menuItemId.slice(4), 10) || null;
    const ok = await saveWith(text, url, title, collectionId);
    notify(ok ? '已收藏到所选分类' : '收藏失败：请先在弹窗配置 WebDAV');
  }
});

/** 收藏（带可选分类与来源页标题），写入云端成功后通知桌面端实时同步。 */
async function saveWith(text, url, title, collectionId) {
  try {
    const cfg = await loadConfig();
    if (!cfg.url) return false;
    const snap = (await davGet(cfg)) || emptySnapshot();
    if (!snap.rows) snap.rows = {};
    appendCard(snap, text, '', { url, title, collectionId });
    await davPut(cfg, snap); // davPut 内部会 pingDesktop
    return true;
  } catch (e) {
    console.error('memcoach save failed', e);
    return false;
  }
}

/** 收藏当前网页：卡面 prompt=页面标题，answer=URL，originalUrl/sourceTitle 同源。 */
async function savePageWith(url, title, collectionId) {
  if (!url) return false;
  try {
    const cfg = await loadConfig();
    if (!cfg.url) return false;
    const snap = (await davGet(cfg)) || emptySnapshot();
    if (!snap.rows) snap.rows = {};
    appendCard(snap, title || url, url, { url, title, collectionId });
    await davPut(cfg, snap);
    return true;
  } catch (e) {
    console.error('memcoach save page failed', e);
    return false;
  }
}

function emptySnapshot() {
  return {
    app: 'memcoach',
    version: '0.1.0',
    exported_at: new Date().toISOString(),
    rows: {
      collections: [], items: [], cards: [],
      review_logs: [], item_collections: [], item_tags: [],
    },
  };
}

function notify(msg) {
  chrome.action.setBadgeText({ text: msg.startsWith('已') ? '✓' : '!' });
  chrome.action.setBadgeBackgroundColor({ color: '#2F6BFF' });
  setTimeout(() => chrome.action.setBadgeText({ text: '' }), 3000);
}