#!/usr/bin/env bash
# android-lib-reader: 从 Gradle 缓存提取/反编译 Android 依赖库源码
# 缓存目录: ~/.gradle/android-lib-reader/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载模块
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/cache-ops.sh"
source "${SCRIPT_DIR}/version.sh"
source "${SCRIPT_DIR}/decompile.sh"
source "${SCRIPT_DIR}/cmd-find-source.sh"
source "${SCRIPT_DIR}/cmd-find-class.sh"
source "${SCRIPT_DIR}/cmd-index-all.sh"
source "${SCRIPT_DIR}/cmd-utils.sh"

# ── 帮助信息 ──
usage() {
  cat <<'EOF'
android-lib-reader — 从 Gradle 缓存提取 Android 依赖库源码

用法:
  lib-reader.sh init
    环境检查与初始化（检查工具链、Gradle 缓存、索引状态）

  lib-reader.sh find-source <groupId> <artifactId> [version]
    提取指定库的源码到缓存目录（省略 version 时从项目 build.gradle 自动解析）

  lib-reader.sh find-class <full.class.Name>
    通过完整类名自动定位并提取源码（自动匹配项目使用的版本）

  lib-reader.sh search <keyword>
    在 Gradle 缓存中搜索匹配的库

  lib-reader.sh tree <groupId> <artifactId> <version>
    列出已提取库的文件结构

  lib-reader.sh list
    列出所有已缓存的库

  lib-reader.sh index-all
    全量索引：扫描所有 source JAR + 编译 JAR + AAR 建立类名索引（推荐首次使用时运行）

  lib-reader.sh rebuild-index
    为所有已缓存的库重建类名索引

  lib-reader.sh clean
    清除所有缓存

环境变量:
  PROJECT_ROOT  指定 Android 项目根目录（默认为当前目录）
EOF
}

# ── 命令路由 ──
case "${1:-help}" in
  init)
    cmd_init
    ;;
  find-source)
    [ $# -lt 3 ] && { echo "用法: $0 find-source <groupId> <artifactId> [version]"; exit 1; }
    _fs_ver="${4:-}"
    if [ -z "$_fs_ver" ]; then
      _fs_ver=$(resolve_project_version "$2" "$3")
      if [ -z "$_fs_ver" ]; then
        _fs_ver=$(ls -1 "${GRADLE_CACHE}/$2/$3/" 2>/dev/null | sort -V | tail -1)
      fi
      [ -z "$_fs_ver" ] && { echo "ERROR:无法确定版本号，请手动指定"; exit 1; }
      echo "AUTO_VERSION:${_fs_ver}"
    fi
    cmd_find_source "$2" "$3" "$_fs_ver"
    ;;
  find-class)
    [ $# -lt 2 ] && { echo "用法: $0 find-class <full.class.Name>"; exit 1; }
    cmd_find_class "$2"
    ;;
  search)
    [ $# -lt 2 ] && { echo "用法: $0 search <keyword>"; exit 1; }
    cmd_search_libs "$2"
    ;;
  tree)
    [ $# -lt 4 ] && { echo "用法: $0 tree <groupId> <artifactId> <version>"; exit 1; }
    cmd_tree "$2" "$3" "$4"
    ;;
  list)
    cmd_list_cached
    ;;
  rebuild-index)
    cmd_rebuild_index
    ;;
  index-all)
    cmd_index_all
    ;;
  clean)
    cmd_clean
    ;;
  *)
    usage
    ;;
esac
