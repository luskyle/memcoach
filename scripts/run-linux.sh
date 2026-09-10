#!/usr/bin/env bash
# 记忆教练 Linux 桌面快速启动（debug 版）
# 使用前需先构建：flutter build linux --debug
# 构建产物落在 build/ 下（不入库），首次启动需完成后台组装步骤。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/build/linux/x64/debug/dist"

if [ ! -x "$DIST/memcoach" ]; then
  echo "未找到构建产物，请先执行："
  echo "  cd $ROOT"
  echo "  flutter build linux --debug"
  echo "  然后 cmake --install 到 $DIST（或参考 README）"
  exit 1
fi

export DISPLAY="${DISPLAY:-:0}"
# NVIDIA 专有驱动：强制 glvnd 使用 nvidia EGL vendor（否则 libEGL 会落到
# mesa 的 DRI2 路径，对 nvidia_drm 无法认证 → 软件渲染，CPU 高占用）
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
cd "$DIST"
exec ./memcoach "$@"