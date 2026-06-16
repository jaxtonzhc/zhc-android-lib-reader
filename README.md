# zhc-android-lib-reader

> Let AI Agents read Gradle dependency library source code directly — just like Android Studio.

[中文版](README.zh.md)

---

## Features

- **Read source by class name** — Give a class name (e.g. `Gson` or `com.google.gson.Gson`), auto-locate and extract source code
- **Read source by Maven coordinate** — Give a coordinate (e.g. `com.google.code.gson:gson:2.11.0`), extract the entire library
- **Search library source** — Search keywords across extracted library source code
- **List library structure** — View the package structure and file listing of a library
- **Auto version matching** — Automatically parse the actual library version from project `build.gradle` or `libs.versions.toml` (supports `version.ref`)
- **Cross-session cache** — Extracted results persist across sessions
- **Binary search index** — Class lookup in **~0.1s** via sorted lookup file + `look` command
- **Custom Gradle home** — Supports `GRADLE_USER_HOME` environment variable

## Quick Start

### Prerequisites

- macOS / Linux
- `bash`, `unzip`, `find`
- An Android project that has been Gradle-synced (cached in `~/.gradle/caches/`)
- Optional: [jadx](https://github.com/skylot/jadx) (for decompiling libraries without source JARs)

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

## Usage

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
# First use: check environment and build index (~1 minute, one-time)
./scripts/lib-reader.sh init
./scripts/lib-reader.sh index-all

# Set project path to enable auto version matching
export PROJECT_ROOT=/path/to/your/android/project

# Read source by class name (supports simple name or FQCN)
./scripts/lib-reader.sh find-class Gson
./scripts/lib-reader.sh find-class com.squareup.okhttp3.OkHttpClient

# Read source by Maven coordinate
./scripts/lib-reader.sh find-source com.google.code.gson gson 2.11.0
```

### Real-World Query Examples

Below are actual query results demonstrating how the tool finds library source code:

```bash
# Simple class name → fuzzy match to FQCN
$ ./scripts/lib-reader.sh find-class Gson
FUZZY_MATCH:Gson -> com.google.gson.Gson
FOUND:.../gson-2.8.5-sources.jar!com/google/gson/Gson.java
COORD:com.google.code.gson:gson:2.8.5
SOURCE:index
---SOURCE---
package com.google.gson;
...

# FQCN → exact match via index
$ ./scripts/lib-reader.sh find-class okhttp3.OkHttpClient
FOUND:.../okhttp-3.14.9-sources.jar!okhttp3/OkHttpClient.java
COORD:com.squareup.okhttp3:okhttp:3.14.9
SOURCE:index

# Internal SDK class → fuzzy match works too
$ ./scripts/lib-reader.sh find-class MMOkHttpDns
FUZZY_MATCH:MMOkHttpDns -> com.immomo.mmdns.MMOkHttpDns
FOUND:.../mmdns-2.2.16.noweb2-sources.jar!com/immomo/mmdns/MMOkHttpDns.java
COORD:com.immomo.mmdns:mmdns:2.2.16.noweb2

# AndroidX classes
$ ./scripts/lib-reader.sh find-class androidx.lifecycle.ViewModel
FOUND:.../lifecycle-viewmodel-2.3.0-sources.jar!androidx/lifecycle/ViewModel.java
COORD:androidx.lifecycle:lifecycle-viewmodel:2.3.0
```

### How AI Agents Should Query

When an AI Agent encounters a class it cannot find in the project source:

1. **Use `find-class` with the FQCN** (preferred): `find-class com.example.SomeClass`
2. **Use `find-class` with simple name** when FQCN is unknown: `find-class SomeClass`
3. **Use `find-source`** when you know the Maven coordinate: `find-source com.example group artifact`
4. **Use `search`** when you don't know the exact class name: `search someKeyword`

## find-class Search Strategy

### Layer 0: Index Lookup (O(log n), ~0.1s)

Uses `look` command for binary search on the sorted `class-lookup.txt`. Supports both exact match (`com.google.gson.Gson`) and fuzzy match by simple class name (`Gson`). When multiple candidates exist, the project version is preferred.

### Layer 1: Parallel Source JAR Scan (~10s)

When the class is not found in the index, scans all source JARs in Gradle cache using 8-way parallel `unzip -Z -1 | grep`. Newly found classes are automatically indexed for future instant lookups.

### Layer 2: Decompilation (Fallback)

When no source JAR exists, the tool decompiles `.jar` or `classes.jar` inside `.aar` files using a **fallback chain** of 3 decompilers:

| Priority | Decompiler | How to Install | Notes |
|----------|-----------|---------------|-------|
| 1 | [jadx](https://github.com/skylot/jadx) | `brew install jadx` | Best quality; failure is final (no fallback) |
| 2 | [CFR](https://www.benf.org/other/cfr/) | `bash scripts/fetch-decompilers.sh` | Robust for complex/obfuscated code |
| 3 | Fernflower | `bash scripts/fetch-decompilers.sh` | IntelliJ's decompiler, good readability |

**Fallback behavior**: jadx failure is final. CFR and Fernflower automatically retry each other — if one produces no output, the other is tried. No Java version binding; selection is purely based on availability.

## First-Time Index Building

When you run `index-all` for the first time, the tool builds a complete class index from all Gradle-cached libraries:

```bash
$ ./scripts/lib-reader.sh index-all
=== Building class index (no source extraction) ===
Phase 1/3: Scanning 936 source JARs (parallel)...
  Scanned 936 JARs

Phase 2/3: Indexing 2094 compiled JARs...
  Added 741286 compiled class indexes

Phase 3/3: Indexing 687 AARs...
  Added 19591 compiled class indexes

Building sorted lookup file...
=== Done: 2770 libraries, 149294 classes indexed ===
```

**What happens in each phase:**
- **Phase 1**: Scans `-sources.jar` files using `unzip -Z -1` to extract class names (no JVM needed, fast)
- **Phase 2**: Scans compiled `.jar` files using `jar tf` to extract `.class` file names
- **Phase 3**: Extracts `classes.jar` from `.aar` archives and scans class names

The index is **incremental** — running `index-all` again skips already-indexed libraries. Typical first run takes ~1 minute for ~1000 libraries.

## Cache Structure

```
~/.gradle/android-lib-reader/
├── sources/              # Extracted source JARs (legacy dir-based extraction)
│   └── <groupId>/<artifactId>/<version>/
├── decompiled/           # Decompiled output (jadx/CFR/Fernflower)
│   └── <groupId>/<artifactId>/<version>/
├── index.tsv             # Library coordinate → cache path (TSV format)
├── class-index.txt       # Inverted index (library → class list)
└── class-lookup.txt      # Sorted lookup (class → library, for binary search)
```

### Index Files

- **`class-index.txt`** — Write-optimized inverted index, grouped by library coordinate with `##########` separators
- **`class-lookup.txt`** — Read-optimized sorted file, one `class_name\tlibrary_coord` per line, deduplicated by class name for `look` binary search
- **`index.tsv`** — TSV file mapping `coord\ttype\tpath\ttimestamp` for each indexed library

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_ROOT` | Android project root for version matching | Current directory |
| `GRADLE_USER_HOME` | Custom Gradle home directory | `~/.gradle` |

## Script Architecture

```
scripts/
├── lib-reader.sh         # Entry point + command router (~100 lines)
├── common.sh             # Global variables + utilities (supports GRADLE_USER_HOME)
├── cache-ops.sh          # Index read/write operations
├── version.sh            # Project-aware version resolution (build.gradle + version catalog)
├── decompile.sh          # Multi-decompiler unified module (jadx > CFR > Fernflower)
├── cmd-find-source.sh    # find-source command
├── cmd-find-class.sh     # find-class command (index + parallel scan)
├── cmd-index-all.sh      # index-all full indexing (3-phase parallel)
├── cmd-utils.sh          # search/tree/list/rebuild/clean/init
├── _scan-jar-worker.sh   # Phase 1 parallel worker
└── fetch-decompilers.sh  # Download bundled CFR + Fernflower
```

## License

MIT
