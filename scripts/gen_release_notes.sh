#!/usr/bin/env bash
# 生成记忆教练发布说明（GitHub Release notes）。
# 从 git log 提取两个标签之间的提交，按 Conventional Commits 风格分组输出中文 Markdown。
#
# 用法: gen_release_notes.sh NEW_TAG [PREV_TAG]
#   NEW_TAG  目标版本标签（如 v0.2.0）
#   PREV_TAG 上一个版本标签；省略时自动取最新的旧 v* 标签（首次发布则列出全历史）
set -euo pipefail

NEW_TAG="${1:?用法: gen_release_notes.sh NEW_TAG [PREV_TAG]}"
PREV_TAG="${2:-}"

# ---- 确定提交范围 ----
if [ -z "$PREV_TAG" ]; then
  PREV_TAG="$(git tag --sort=-v:refname | grep -E '^v' | grep -v "^${NEW_TAG}$" | head -1 || true)"
fi

END_REF="HEAD"
if git rev-parse -q --verify "refs/tags/${NEW_TAG}" >/dev/null 2>&1; then
  END_REF="$NEW_TAG"
fi

EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
if [ -n "$PREV_TAG" ]; then
  RANGE="$PREV_TAG..$END_REF"
  RANGE_LABEL="$PREV_TAG → $NEW_TAG"
  BASE_REF="$PREV_TAG"
else
  RANGE="$END_REF"
  RANGE_LABEL="初始发布（全部历史）"
  BASE_REF="$EMPTY_TREE"
fi

# ---- 分类 ----
classify() {
  case "$1" in
    feat*|feature*|新增*|支持*|实现*) echo feat ;;
    fix*|修复*|解决*|bug*) echo fix ;;
    perf*|优化*|性能*) echo perf ;;
    refactor*|重构*) echo refactor ;;
    docs*|文档*) echo docs ;;
    test*|测试*) echo test ;;
    chore*|build*|ci*|工程*|依赖*) echo chore ;;
    *) echo other ;;
  esac
}

declare -a items_feat items_fix items_perf items_refactor items_docs items_test items_chore items_other
COMMITS=0

# 收集（进程替换保持在同一 shell 中执行，数组与计数才能生效）
while IFS= read -r subject; do
  subject="${subject%"${subject##*[![:space:]]}"}"
  [ -z "$subject" ] && continue
  COMMITS=$((COMMITS + 1))
  case "$(classify "$subject")" in
    feat) items_feat+=("$subject") ;;
    fix) items_fix+=("$subject") ;;
    perf) items_perf+=("$subject") ;;
    refactor) items_refactor+=("$subject") ;;
    docs) items_docs+=("$subject") ;;
    test) items_test+=("$subject") ;;
    chore) items_chore+=("$subject") ;;
    other) items_other+=("$subject") ;;
  esac
done < <(git log --pretty='%s' "$RANGE")

FILES="$(git diff --name-only "$BASE_REF" "$END_REF" 2>/dev/null | wc -l | tr -d ' ')"
[ -z "$FILES" ] && FILES=0

# ---- 分组输出 ----
print_group() {
  local title list=()
  case "$1" in
    feat) title="功能"; list=("${items_feat[@]}") ;;
    fix) title="修复"; list=("${items_fix[@]}") ;;
    perf) title="性能"; list=("${items_perf[@]}") ;;
    refactor) title="重构"; list=("${items_refactor[@]}") ;;
    docs) title="文档"; list=("${items_docs[@]}") ;;
    test) title="测试"; list=("${items_test[@]}") ;;
    chore) title="工程"; list=("${items_chore[@]}") ;;
    other) title="其他"; list=("${items_other[@]}") ;;
  esac
  [ "${#list[@]}" -eq 0 ] && return
  printf '## %s\n\n' "$title"
  for item in "${list[@]}"; do
    printf -- '- %s\n' "$item"
  done
  printf '\n'
}

printf '# 记忆教练 %s\n\n' "$NEW_TAG"
printf '> 数据范围：%s · 提交 %d 个 · 变更文件 %d 个\n\n' "$RANGE_LABEL" "$COMMITS" "$FILES"
printf '把你想记住的任何东西收进来，它会在对的时间提醒你复习。\n\n'

print_group feat
print_group fix
print_group perf
print_group refactor
print_group docs
print_group test
print_group chore
print_group other

cat <<'EOF'
## 📦 下载安装

- **Android**：下载 `memcoach-v*.apk` 直接安装。
- **Linux**：下载 `memcoach-linux-x64.tar.gz`，解压后运行 `bundle/memcoach`。
- **iOS**：当前产物为**未签名** Runner.app（zip），需 Apple 开发者证书签名后分发。

> 数据说明：收藏与复习数据默认仅保存在本机；可在「设置 → 导出我的收藏库」导出 JSON。
> 隐私承诺：服务器不存储任何媒体文件。
EOF