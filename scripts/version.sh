#!/usr/bin/env bash
# 项目版本解析：从 build.gradle / version catalog 中提取依赖版本

resolve_project_version() {
  local group_id="$1" artifact_id="$2"
  [ ! -d "$PROJECT_ROOT" ] && return

  local pattern="${group_id}:${artifact_id}:"
  local match

  # 1. 搜索变量引用: "com.xxx:yyy:$varName" → 再找变量定义
  local var_name
  var_name=$(rg --no-filename \
    "^[^/]*${pattern}\\\$" \
    "${PROJECT_ROOT}" --glob "*.gradle" --glob "*.gradle.kts" \
    2>/dev/null | grep -v '^\s*//' | grep -oE '\$[a-zA-Z_][a-zA-Z0-9_]*' | head -1 | tr -d '$')

  if [ -n "$var_name" ]; then
    match=$(rg --no-filename \
      "${var_name}\s*=\s*['\"]" \
      "${PROJECT_ROOT}" --glob "*.gradle" --glob "*.gradle.kts" \
      2>/dev/null | grep -v '^\s*//' | grep -oE "['\"][^'\"]+['\"]" | head -1 | tr -d "\"'")
    if [ -n "$match" ]; then
      echo "$match"
      return
    fi
  fi

  # 2. 直接搜索硬编码版本: "com.xxx:yyy:1.2.3"
  match=$(rg --no-filename \
    "^[^/]*${pattern}" \
    "${PROJECT_ROOT}" --glob "*.gradle" --glob "*.gradle.kts" --glob "*.toml" \
    2>/dev/null | grep -v '^\s*//' | grep -oE "${pattern}[0-9][^\"')]*" | head -1)

  if [ -n "$match" ]; then
    echo "${match#${pattern}}"
    return
  fi

  # 3. 搜索 version catalog (.toml)
  match=$(rg --no-filename \
    "module\s*=\s*\"${group_id}:${artifact_id}\"" -A2 \
    "${PROJECT_ROOT}" --glob "*.toml" \
    2>/dev/null | grep -oE 'version\s*=\s*"[^"]+' | head -1 | grep -oE '"[^"]+' | tr -d '"')

  if [ -n "$match" ]; then
    echo "$match"
  fi
}
