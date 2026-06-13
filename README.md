# zhc-android-lib-reader

> Let AI Agents read Gradle dependency library source code directly — just like Android Studio.

[中文版](README.zh.md)

---

## ✨ Features

- **Read source by class name** — Give a class name (e.g. `Gson` or `com.google.gson.Gson`), auto-locate and extract source code
- **Read source by Maven coordinate** — Give a coordinate (e.g. `com.google.code.gson:gson:2.11.0`), extract the entire library
- **Search library source** — Search keywords across extracted library source code
- **List library structure** — View the package structure and file listing of a library
- **Auto version matching** — Automatically parse the actual library version from project `build.gradle`
- **Cross-session cache** — Extracted results persist across sessions
- **Binary search index** — Class lookup in **0.002s** via sorted lookup file + `look` command

## 🚀 Quick Start

### Prerequisites

- macOS / Linux
- `bash`, `unzip`, `find`
- An Android project that has been Gradle-synced (cached in `~/.gradle/caches/`)
- Optional: [jadx](https://github.com/skylot/jadx) (for decompiling libraries without source JARs; auto-installed via `brew install jadx` if missing)

### Installation

```bash
# 1. Clone the repository
git clone git@github.com:jaxtonzhc/zhc-android-lib-reader.git
cd zhc-android-lib-reader

# 2. One-click install to all AI Agents (Cursor, Codex, Claude Code, etc.)
bash install.sh

# 3. Initialize and build index
./scripts/lib-reader.sh init
./scripts/lib-reader.sh index-all
```

The `install.sh` script auto-detects and creates symlinks in `~/.cursor/skills/`, `~/.codex/skills/`, `~/.claude/skills/`, `~/.agents/skills/`, and `~/.hermes/skills/`.

You can also install manually:

```bash
ln -sf /path/to/zhc-android-lib-reader ~/.cursor/skills/zhc-android-lib-reader
```

## 📖 Usage

### Command Reference

| Command | Description | Example |
|---------|-------------|---------|
| `init` | Environment check and setup | `lib-reader.sh init` |
| `find-class <className>` | Find and extract source by class name | `lib-reader.sh find-class Gson` |
| `find-source <gid> <aid> [ver]` | Extract source by Maven coordinate | `lib-reader.sh find-source com.squareup.okhttp3 okhttp` |
| `search <keyword>` | Fuzzy search libraries in Gradle cache | `lib-reader.sh search retrofit` |
| `tree <gid> <aid> <ver>` | List extracted library file structure | `lib-reader.sh tree com.google.code.gson gson 2.8.6` |
| `list` | List all cached libraries | `lib-reader.sh list` |
| `index-all` | Full index (recommended on first use) | `lib-reader.sh index-all` |
| `rebuild-index` | Rebuild class name index for cached libs | `lib-reader.sh rebuild-index` |
| `clean` | Clear all cache | `lib-reader.sh clean` |

### Examples

```bash
# First use: check environment and build index
./scripts/lib-reader.sh init
./scripts/lib-reader.sh index-all

# Set project path to enable auto version matching
export PROJECT_ROOT=/path/to/your/android/project

# Read source by class name (supports simple name or FQCN)
./scripts/lib-reader.sh find-class Gson
./scripts/lib-reader.sh find-class com.squareup.okhttp3.OkHttpClient

# Read entire library by Maven coordinate
./scripts/lib-reader.sh find-source com.google.code.gson gson 2.11.0
```

## 🔍 find-class Search Strategy

### Step 1: Index Lookup (O(log n), ~0.002s)

Uses `look` command for binary search on the sorted `class-lookup.txt`. Supports both exact match (`com.google.gson.Gson`) and fuzzy match by simple class name (`Gson`).

### Step 2: Source JAR Extraction

Most open-source libraries publish a `-sources.jar`. Gradle downloads it to local cache during sync. The tool extracts it directly — no decompilation needed.

### Step 3: JAR/AAR Decompilation (Fallback)

When no source JAR exists, the tool decompiles `.jar` or `classes.jar` inside `.aar` files using a **fallback chain** of 3 decompilers:

| Priority | Decompiler | How to Install | Notes |
|----------|-----------|---------------|-------|
| 1 | [jadx](https://github.com/skylot/jadx) | `brew install jadx` | Best quality; failure is final (no fallback) |
| 2 | [CFR](https://www.benf.org/other/cfr/) | `bash scripts/fetch-decompilers.sh` | Robust for complex/obfuscated code |
| 3 | Fernflower | `bash scripts/fetch-decompilers.sh` | IntelliJ's decompiler, good readability |

**Fallback behavior**: jadx failure is final. CFR and Fernflower automatically retry each other — if one produces no output, the other is tried. No Java version binding; selection is purely based on availability.

### Step 4: Gradle On-Demand Download

When no source JAR is found in the Gradle cache, triggers a Gradle task to download it.

## 📁 Cache Structure

```
~/.gradle/android-lib-reader/
├── sources/              # Extracted source JARs
│   └── <groupId>/<artifactId>/<version>/
├── decompiled/           # Decompiled output (jadx)
│   └── <groupId>/<artifactId>/<version>/
├── index.json            # Library coordinate → cache path
├── class-index.txt       # Inverted index (library → class list)
└── class-lookup.txt      # Sorted lookup (class → library, for binary search)
```

### Index Files

- **`class-index.txt`** — Write-optimized inverted index, grouped by library coordinate with `##########` separators
- **`class-lookup.txt`** — Read-optimized sorted file, one `class_name\tlibrary_coord` per line, deduplicated by class name for `look` binary search

## 🏗 Script Architecture

```
scripts/
├── lib-reader.sh         # Entry point + command router (100 lines)
├── common.sh             # Global variables + utilities
├── cache-ops.sh          # Index read/write operations
├── version.sh            # Project-aware version resolution
├── cmd-find-source.sh    # find-source command
├── cmd-find-class.sh     # find-class command
├── cmd-index-all.sh      # index-all full indexing
└── cmd-utils.sh          # search/tree/list/rebuild/clean/init
```

## 📝 License

MIT
