# 记忆教练 · 浏览器划词收藏插件

划词 / 摘录 → 收藏到记忆教练。数据写入**你自己配置的 WebDAV 云盘**（坚果云等），
桌面与移动端打开记忆教练会自动合并进收件箱——服务器零存储，与 App 共用同一份快照契约。

## 安装（Chrome / Edge）

1. 打开扩展管理页：`chrome://extensions`（Edge：`edge://extensions`）
2. 右上角打开「开发者模式」
3. 点「加载已解压的扩展程序」→ 选择本目录 `browser-extension/`

## 使用

- **划词 → 右键 → 「收藏到记忆教练」**：立即收藏（默认未分类，明天开始复习）
- **划词 → 右键 → 「收藏到记忆教练（选分类…）」**：打开弹窗选择分类后收藏
- 点击浏览器工具栏的记忆教练图标：手动输入内容 + 选分类收藏

## 配置（首次必做）

弹窗 → 「设置」→ 填写：

| 项 | 说明 | 示例 |
|---|---|---|
| 地址 | WebDAV 服务地址 | `https://dav.jianguoyun.com/dav/`（坚果云） |
| 账号 | 云盘账号 | 坚果云登录邮箱 |
| 密码 | **应用密码**（不是登录密码） | 坚果云 → 账户信息 → 安全选项 → 应用密码 |

保存后自动拉取云端分类（下拉可选）。

## 数据与契约

- 云端文件：`<WebDAV 地址>/memcoach/backup.json`（与 App 云盘同步同一文件）
- 字段与 App 快照一致（camelCase；日期 ISO8601；条目 id 用负值避免与 App 冲突）
- 插件写入的条目 `status=inbox`（App 收件箱显示「待归类」，可再整理分类）
  ／`learning`（弹窗收藏直接进入复习队列，明天首复）
- 桌面/移动端打开 App → 启动自动 `syncNow` 拉取合并 → 条目入收件箱/记忆库

## 本地联调（无云盘时）

```bash
# 1. 起本地 WebDAV（需要 python + pip install wsgidav cheroot lxml）
mkdir -p /tmp/memcoach-dav && wsgidav -r /tmp/memcoach-dav --host 127.0.0.1 --port 8080 --auth anonymous

# 2. App「设置 → 云盘备份」：WebDAV 地址填 http://127.0.0.1:8080（账号密码留空）→ 保存

# 3. 插件设置同填 http://127.0.0.1:8080 → 划词收藏 → App 重启自动合并

# 验证（可选）：真实走一遍同步引擎
WEBDAV_URL=http://127.0.0.1:8080 flutter test test/live_webdav_test.dart
```

## 局限（V1）

- 仅 WebDAV 通道（iCloud 是 iOS 专属，插件无法访问）
- 剪藏只存引用（原文 URL）+ 文本；不托管全文
- 同名分类冲突时以先到为准（负 id 幂等合并）