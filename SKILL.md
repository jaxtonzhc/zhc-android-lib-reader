---
name: zhc-android-lib-reader
version: 1.0.0
description: "Automatically locate and read source code for any class, interface, or annotation NOT found in the project's git-tracked source files. Triggers: (1) a class/interface referenced in code or import cannot be found by Grep/Glob in the workspace — e.g. 'class not found', 'cannot resolve symbol', 'no definition found for XxxClass'; (2) need to understand the internal implementation, constructor, callback, or exception behavior of a third-party or internal SDK class; (3) user explicitly asks to read library source. Covers all Android Gradle/Maven dependencies including AAR, JAR, internal Nexus packages. Auto extracts from Gradle cache source JARs with jadx decompile fallback and cross-session cache. Trigger words: class not found, cannot resolve symbol, no definition found, read library source, view library implementation, dependency source, third-party SDK source, lib source, lib-read, lib-search, lib-list."
compatibility:
  os: [macos, linux]
  tools: [cursor, claude, codex, copilot, gemini, openclaw, hermes]
alwaysApply: true
---

# Android Library Source Reader

> Let AI Agents read Gradle dependency library source code directly — just like Android Studio.

## Core Capabilities

1. **Read source by class name** — Give a fully qualified class name (e.g. `com.google.gson.Gson`), auto-locate and extract source code
2. **Read source by Maven coordinate** — Give a coordinate (e.g. `com.google.code.gson:gson:2.11.0`), extract the entire library
3. **Search library source** — Search keywords across extracted library source code
4. **List library structure** — View the package structure and file listing of a library
5. **Auto version matching** — Automatically parse the actual library version from project `build.gradle` or `libs.versions.toml`


## Prerequisites

| Tool | Required | Install |
|------|----------|--------|
| jadx | Yes (for decompilation) | `brew install jadx` |
| python3 | Yes | macOS: pre-installed or `brew install python3` |
| rg (ripgrep) | Yes | `brew install ripgrep` |
| jar | Yes (JDK) | Install JDK: `brew install openjdk` |
| unzip | Yes | macOS: pre-installed |

> **Note**: jadx is the primary decompiler used when no `-sources.jar` is available. Without it, decompilation of compiled `.class` files will fail. The tool also bundles CFR/Fernflower as fallbacks (run `scripts/fetch-decompilers.sh` to download them).

## First Use

When this skill is triggered for the first time (no `~/.gradle/android-lib-reader/class-lookup.txt` or it has fewer than 100 entries):

1. **Run `init`** to verify environment:
   ```bash
   scripts/lib-reader.sh init
   ```
2. **Run `index-all`** to build the full class index (~1 minute, one-time):
   ```bash
   PROJECT_ROOT=/path/to/android/project scripts/lib-reader.sh index-all
   ```
3. After indexing, all `find-class` calls will achieve instant lookup (~0.1s) via binary search.

The AI Agent should check if the index exists before first use and guide the user through setup if needed.

## Trigger Conditions

**MUST trigger** whenever the AI Agent encounters any of these situations during normal development work (bug fixing, feature implementation, code review, etc.):

- **Class/symbol not found**: Grep or Glob for a class name returns zero results in the workspace — the class is from a dependency, not project source. **Do NOT report "class not found" to the user; use this skill to find and read it.**
- **Import without definition**: Code imports a class (e.g. `import com.xxx.yyy.ZzzClass`) but no `.kt`/`.java` file defining it exists in the project
- **Understanding library behavior**: Need to check how a third-party API works internally — constructor params, callback interfaces, exception types, default values
- **Debugging through SDK code**: Stack trace or crash points to a library class; need to read the source to understand the failure
- **API contract verification**: Need to confirm method signatures, return types, or threading guarantees of a dependency class
- **User explicitly requests**: "read library source", "show me the implementation of XxxClass", "阅读库源码"

> **Key principle**: When you cannot find a class definition in the project, your FIRST action should be to use this skill — not to tell the user "I can't find the class".

## Decompiler Architecture

The tool supports 3 decompilers with automatic selection and **fallback chain**:

| Priority | Decompiler | Source | Notes |
|----------|-----------|--------|-------|
| 1 (highest) | jadx | `brew install jadx` | Best quality; failure is final (no fallback) |
| 2 | CFR | Bundled JAR (`scripts/decompilers/cfr.jar`) | Robust for complex generics and obfuscated code |
| 3 | Fernflower | Bundled JAR (`scripts/decompilers/fernflower.jar`) | IntelliJ's decompiler, good readability |

**Selection logic** (`_select_decompiler`): No Java version binding — selection is purely based on availability:
1. If `jadx` is on `$PATH` → use jadx
2. Else if `cfr.jar` exists → use CFR
3. Else if `fernflower.jar` exists → use Fernflower
4. Else → error, no decompiler available

**Fallback chain** (`decompile_jar`):
- **jadx**: No fallback. If jadx fails, the artifact is genuinely broken — returns error immediately.
- **CFR → Fernflower**: If CFR produces no output, automatically retries with Fernflower (and vice versa).
- If all fallbacks exhausted → returns error with actionable message.

**Setup bundled decompilers** (no jadx required):
```bash
bash scripts/fetch-decompilers.sh
```

This downloads CFR 0.152 from Maven Central and Fernflower from JetBrains Maven repository.

**Design principles**:
- `decompile_jar` owns selection + execution + fallback — callers don't need to know which decompiler is used.
- `ensure_decompiler` only checks/installs, never called in find-source critical path (no blocking `brew install`).


## Lookup Strategy

### Layer 1: Source JAR Extraction (Fastest, covers ~90% of open-source libraries)

Most open-source libraries publish a `-sources.jar` alongside the main artifact. Gradle downloads it to local cache during sync.

```
~/.gradle/caches/modules-2/files-2.1/<groupId>/<artifactId>/<version>/
  ├── <hash>/<artifactId>-<version>.jar          # Compiled artifact
  ├── <hash>/<artifactId>-<version>-sources.jar   # Source ✅
  └── <hash>/<artifactId>-<version>.pom           # Metadata
```

**Steps**:
```bash
# 1. Find source JAR
SOURCE_JAR=$(find ~/.gradle/caches/modules-2/files-2.1/<groupId>/<artifactId>/<version> \
  -name "*-sources.jar" -type f 2>/dev/null | head -1)

# 2. Read target class file directly from JAR (no extraction to disk)
# Convert class name com.google.gson.Gson to path com/google/gson/Gson.java
unzip -p "$SOURCE_JAR" "com/google/gson/Gson.java"
```

### Layer 2: JAR/AAR Decompilation (Fallback when no source available)

When no source JAR exists, uses the decompiler fallback chain to decompile `.jar` or `classes.jar` inside `.aar` files.

```bash
# 1. Find compiled artifact
ARTIFACT=$(find ~/.gradle/caches/modules-2/files-2.1/<groupId>/<artifactId>/<version> \
  \( -name "*.jar" -not -name "*-sources.jar" -not -name "*-javadoc.jar" \) \
  -o -name "*.aar" 2>/dev/null | head -1)

# 2. If AAR, extract classes.jar first
if [[ "$ARTIFACT" == *.aar ]]; then
  unzip -o -q "$ARTIFACT" classes.jar -d /tmp/aar-extract/
  ARTIFACT=/tmp/aar-extract/classes.jar
fi

# 3. Decompile (auto-selects best available decompiler)
CACHE_DIR=~/.gradle/android-lib-reader/decompiled/<groupId>/<artifactId>/<version>
# decompile_jar handles jadx/CFR/Fernflower selection and fallback automatically
```

## Cache Design

### Cache Directory Structure
```
~/.gradle/android-lib-reader/
├── sources/                                    # Layer 1: Source extraction (legacy, dir-based)
│   └── <groupId>/<artifactId>/<version>/
│       └── com/example/MyClass.java
├── decompiled/                                 # Layer 2: Decompiled output
│   └── <groupId>/<artifactId>/<version>/
│       └── [sources/]com/example/MyClass.java
├── index.tsv                                   # Library coordinate index (TSV format, cross-session)
├── class-index.txt                             # Inverted index (library → classes, human-readable)
└── class-lookup.txt                            # Sorted lookup (class → library, binary search)
```

### index.tsv Format
```
com.google.code.gson:gson:2.11.0	source	/path/to/gson-2.11.0-sources.jar	2026-06-10T17:50:00
com.example.internal:sdk:1.0.0	decompiled	/path/to/decompiled/sources	2026-06-10T18:00:00
```

> **Note**: The index was migrated from `index.json` to `index.tsv` for better performance. Legacy `index.json` files are auto-migrated on first use.

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_ROOT` | Android project root for version matching | Current directory |
| `GRADLE_USER_HOME` | Custom Gradle home directory | `~/.gradle` |

## Script Commands

Script path: `scripts/lib-reader.sh`

```bash
PROJECT_ROOT=/path/to/android/project scripts/lib-reader.sh <command> [args]
```

### Command Reference

| Command | Description | Example |
|---------|-------------|---------|
| `init` | Environment check and setup (tools, Gradle cache, index status) | `scripts/lib-reader.sh init` |
| `find-source <gid> <aid> [ver]` | Extract library source (auto-resolve version from project when omitted) | `scripts/lib-reader.sh find-source com.squareup.okhttp3 okhttp` |
| `find-class <className>` | Find and extract source by class name with auto version matching | `scripts/lib-reader.sh find-class com.google.gson.Gson` |
| `search <keyword>` | Fuzzy search libraries in Gradle cache | `scripts/lib-reader.sh search retrofit` |
| `tree <gid> <aid> <ver>` | List extracted library file structure | `scripts/lib-reader.sh tree com.google.code.gson gson 2.8.6` |
| `list` | List all cached libraries | `scripts/lib-reader.sh list` |
| `index-all` | Full index (source JAR + compiled JAR + AAR) | `scripts/lib-reader.sh index-all` |
| `rebuild-index` | Rebuild class name index for cached libraries | `scripts/lib-reader.sh rebuild-index` |
| `clean` | Clear all cache | `scripts/lib-reader.sh clean` |

### find-class Search Strategy

`find-class` uses a two-layer progressive search:

1. **Layer 0: Index lookup** (~0.1s) — Binary search via `look` on sorted `class-lookup.txt`. Supports exact match by FQCN and fuzzy match by simple class name. When multiple candidates exist, prefers the version used by the project.
2. **Layer 1: Parallel source JAR scan** (~10s) — 8-way parallel `unzip -Z -1 | grep` across all source JARs in Gradle cache. Falls back here when the class index has no match.

**Recommended**: Run `index-all` once on first use to build the full index. All subsequent `find-class` calls will hit Layer 0 with instant response.

### Version Matching Mechanism

`find-class` and `find-source` (when version is omitted) automatically parse the actual library version from the project:

1. **Variable reference**: `"com.xxx:yyy:$version"` → find variable definition → extract version
2. **Hardcoded version**: `"com.xxx:yyy:1.2.3"` → extract directly
3. **Version Catalog (inline)**: `module = "com.xxx:yyy"` with `version = "1.2.3"` in `.toml`
4. **Version Catalog (ref)**: `module = "com.xxx:yyy"` with `version.ref = "xxx"` → resolves from `[versions]` section

Output includes version match status:
- `VERSION_MATCH:Project uses version X.Y.Z` — Exact match
- `VERSION_WARN:Project uses X.Y.Z, but only found source for A.B.C` — Version mismatch, note caution

## Real-World Query Examples

```bash
# Simple class name → fuzzy match
$ find-class Gson
FUZZY_MATCH:Gson -> com.google.gson.Gson
FOUND:.../gson-2.8.5-sources.jar!com/google/gson/Gson.java
COORD:com.google.code.gson:gson:2.8.5

# FQCN → exact index match (~0.3s)
$ find-class okhttp3.OkHttpClient
FOUND:.../okhttp-3.14.9-sources.jar!okhttp3/OkHttpClient.java
COORD:com.squareup.okhttp3:okhttp:3.14.9

# AndroidX class
$ find-class androidx.lifecycle.ViewModel
FOUND:.../lifecycle-viewmodel-2.3.0-sources.jar!androidx/lifecycle/ViewModel.java

# Internal SDK class
$ find-class MMOkHttpDns
FUZZY_MATCH:MMOkHttpDns -> com.immomo.mmdns.MMOkHttpDns
FOUND:.../mmdns-2.2.16.noweb2-sources.jar!com/immomo/mmdns/MMOkHttpDns.java
```

### AI Agent Query Guide

When you cannot find a class in the project source, use these commands in order of preference:

1. **`find-class <FQCN>`** — Best when you know the full class name from an import statement
2. **`find-class <SimpleName>`** — When you only see the class name without package
3. **`find-source <gid> <aid>`** — When you know the Maven coordinate (version auto-resolved)
4. **`search <keyword>`** — When unsure about class name, search by library keyword

## Notes

- **Prefer source JAR** (Layer 1) over decompilation
- **Version matching**: Always confirm the actual library version used by the project (check `build.gradle` or `gradle.lockfile`)
- **jadx** is required for decompilation fallback. See Prerequisites section above for install instructions.
- **AAR vs JAR**: AAR is Android library format containing `classes.jar`, resources, AndroidManifest, etc.; must extract before decompiling
- **Cache is persistent**: `~/.gradle/android-lib-reader/` persists across sessions
- **Custom Gradle home**: Set `GRADLE_USER_HOME` environment variable if using a non-default Gradle directory
- **Clear cache**: `rm -rf ~/.gradle/android-lib-reader/` to clear; will re-extract on next use
