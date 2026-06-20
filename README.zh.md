# zhc-android-lib-reader

> 让 AI Agent 像 Android Studio 一样直接阅读 Gradle 依赖的库源码。

[English Version](README.md)

---

## 功能特性

- **按类名读源码** — 给出类名（如 `Gson` 或 `com.google.gson.Gson`），自动定位并提取源码
- **按 Maven 坐标读源码** — 给出坐标（如 `com.google.code.gson:gson:2.11.0`），提取整个库
- **搜索库源码** — 在已提取的库源码中搜索关键词
- **列出库目录结构** — 查看库的包结构和文件列表
- **项目版本自动匹配** — 自动从项目 `build.gradle` 或 `libs.versions.toml` 中解析实际使用的库版本（支持 `version.ref`）
- **跨会话缓存** — 提取结果持久化，不会随对话结束消失
- **二分查找索引** — 类名查找仅需 **~0.1s**，基于排序文件 + `look` 命令
- **自定义 Gradle 目录** — 支持 `GRADLE_USER_HOME` 环境变量

## 快速开始

### 前置条件

- macOS / Linux
- `bash`、`unzip`、`find`
- Android 项目已同步过 Gradle（`~/.gradle/caches/` 中有缓存）
- 可选：[jadx](https://github.com/skylot/jadx)（用于反编译无源码的库）

### 安装

**方式 A：通过 `npx skills` 安装（推荐）**

```bash
# 安装到所有支持的 AI Agent（Cursor、Claude Code、Codex、Copilot 等）
npx skills add jaxtonzhc/zhc-android-lib-reader

# 更新到最新版本
npx skills update zhc-android-lib-reader
```

**方式 B：通过 `install.sh` 安装**

```bash
git clone https://github.com/jaxtonzhc/zhc-android-lib-reader.git
cd zhc-android-lib-reader
bash install.sh
```

`install.sh` 会自动检测并创建软链接到 `~/.cursor/skills/`、`~/.codex/skills/`、`~/.claude/skills/`、`~/.agents/skills/`、`~/.hermes/skills/`。

**安装后初始化并建立索引：**

```bash
./scripts/lib-reader.sh init
./scripts/lib-reader.sh index-all
```

## 使用方法

### 脚本命令速查

| 命令 | 说明 | 示例 |
|------|------|------|
| `init` | 环境检查与初始化 | `lib-reader.sh init` |
| `find-class <className>` | 通过类名查找并提取源码 | `lib-reader.sh find-class Gson` |
| `find-source <gid> <aid> [ver]` | 按 Maven 坐标提取源码 | `lib-reader.sh find-source com.squareup.okhttp3 okhttp` |
| `search <keyword>` | 模糊搜索 Gradle 缓存中的库 | `lib-reader.sh search retrofit` |
| `tree <gid> <aid> <ver>` | 列出已提取库的文件结构 | `lib-reader.sh tree com.google.code.gson gson 2.8.6` |
| `list` | 列出所有已缓存的库 | `lib-reader.sh list` |
| `index-all` | 全量索引（推荐首次使用时执行） | `lib-reader.sh index-all` |
| `rebuild-index` | 为已缓存的库重建类名索引 | `lib-reader.sh rebuild-index` |
| `clean` | 清除所有缓存 | `lib-reader.sh clean` |

### 使用示例

```bash
# 首次使用：检查环境并建立索引（约 1 分钟，只需运行一次）
./scripts/lib-reader.sh init
./scripts/lib-reader.sh index-all

# 设置项目路径以启用版本自动匹配
export PROJECT_ROOT=/path/to/your/android/project

# 通过类名读取源码（支持简单类名和完整类名）
./scripts/lib-reader.sh find-class Gson
./scripts/lib-reader.sh find-class com.squareup.okhttp3.OkHttpClient

# 通过 Maven 坐标读取整个库
./scripts/lib-reader.sh find-source com.google.code.gson gson 2.11.0
```

### 实际查询示例

以下是真实的查询结果，展示工具如何定位库源码：

```bash
# 简单类名 → 模糊匹配到完整类名
$ ./scripts/lib-reader.sh find-class Gson
FUZZY_MATCH:Gson -> com.google.gson.Gson
FOUND:.../gson-2.8.5-sources.jar!com/google/gson/Gson.java
COORD:com.google.code.gson:gson:2.8.5
SOURCE:index
---SOURCE---
package com.google.gson;
...

# 完整类名 → 通过索引精确匹配
$ ./scripts/lib-reader.sh find-class okhttp3.OkHttpClient
FOUND:.../okhttp-3.14.9-sources.jar!okhttp3/OkHttpClient.java
COORD:com.squareup.okhttp3:okhttp:3.14.9
SOURCE:index

# 内部 SDK 类 → 同样支持模糊匹配
$ ./scripts/lib-reader.sh find-class MMOkHttpDns
FUZZY_MATCH:MMOkHttpDns -> com.immomo.mmdns.MMOkHttpDns
FOUND:.../mmdns-2.2.16.noweb2-sources.jar!com/immomo/mmdns/MMOkHttpDns.java
COORD:com.immomo.mmdns:mmdns:2.2.16.noweb2

# AndroidX 类
$ ./scripts/lib-reader.sh find-class androidx.lifecycle.ViewModel
FOUND:.../lifecycle-viewmodel-2.3.0-sources.jar!androidx/lifecycle/ViewModel.java
COORD:androidx.lifecycle:lifecycle-viewmodel:2.3.0
```

### AI Agent 查询指引

当 AI Agent 在项目源码中找不到某个类时：

1. **用完整类名查找**（首选）：`find-class com.example.SomeClass`
2. **用简单类名查找**（不知道包名时）：`find-class SomeClass`
3. **用 Maven 坐标查找**（知道库坐标时）：`find-source com.example group artifact`
4. **用关键词搜索**（不确定类名时）：`search someKeyword`

## find-class 查找策略

### Layer 0：索引查找（O(log n)，~0.1s）

使用 `look` 命令对排序后的 `class-lookup.txt` 进行二分查找。支持精确匹配（`com.google.gson.Gson`）和简单类名模糊匹配（`Gson`）。存在多个候选时优先匹配项目使用的版本。

### Layer 1：并行源码 JAR 扫描（~10s）

当索引中找不到类时，使用 8 路并行 `unzip -Z -1 | grep` 扫描 Gradle 缓存中所有 source JAR。新发现的类会自动建立索引供后续即时查找。

### Layer 2：反编译（降级方案）

当 source JAR 不存在时，工具通过**降级链**自动从 3 个反编译器中选择来反编译 `.jar` 或 `.aar` 中的 `classes.jar`：

| 优先级 | 反编译器 | 安装方式 | 说明 |
|--------|---------|---------|------|
| 1 | [jadx](https://github.com/skylot/jadx) | `brew install jadx` | 质量最高；失败即终止（不降级） |
| 2 | [CFR](https://www.benf.org/other/cfr/) | `bash scripts/fetch-decompilers.sh` | 对复杂泛型和混淆代码处理稳健 |
| 3 | Fernflower | `bash scripts/fetch-decompilers.sh` | IntelliJ 内置反编译器，可读性好 |

**降级行为**：jadx 失败不会降级。CFR 和 Fernflower 互相自动降级——如果一个没有产出，自动尝试另一个。不绑定 Java 版本，纯按可用性选择。

## 首次索引建立

首次运行 `index-all` 时，工具会从所有 Gradle 缓存的库中建立完整的类名索引：

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

**各阶段说明：**
- **Phase 1**：使用 `unzip -Z -1` 扫描 `-sources.jar` 中的类名（无需 JVM，速度快）
- **Phase 2**：使用 `jar tf` 扫描编译后的 `.jar` 文件中的 `.class` 文件名
- **Phase 3**：从 `.aar` 中提取 `classes.jar` 并扫描类名

索引是**增量式**的——再次运行 `index-all` 会跳过已索引的库。首次运行约 1 分钟（约 1000 个库）。

## 缓存结构

```
~/.gradle/android-lib-reader/
├── sources/              # 源码提取结果（旧版目录提取方式）
│   └── <groupId>/<artifactId>/<version>/
├── decompiled/           # 反编译结果（jadx/CFR/Fernflower）
│   └── <groupId>/<artifactId>/<version>/
├── index.tsv             # 库坐标 → 缓存路径（TSV 格式）
├── class-index.txt       # 倒排索引（库→类列表）
└── class-lookup.txt      # 排序查找文件（类→库，用于二分查找）
```

### 索引文件说明

- **`class-index.txt`** — 写优化的倒排索引，按库坐标分组，以 `##########` 分隔
- **`class-lookup.txt`** — 读优化的排序文件，每行 `类名\t库坐标`，按类名去重，供 `look` 二分查找
- **`index.tsv`** — TSV 文件，每行格式为 `坐标\t类型\t路径\t时间戳`

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `PROJECT_ROOT` | Android 项目根目录，用于版本自动匹配 | 当前目录 |
| `GRADLE_USER_HOME` | 自定义 Gradle 主目录 | `~/.gradle` |

## 脚本架构

```
scripts/
├── lib-reader.sh         # 入口 + 命令路由（~100 行）
├── common.sh             # 全局变量 + 基础工具（支持 GRADLE_USER_HOME）
├── cache-ops.sh          # 索引读写操作
├── version.sh            # 项目版本自动解析（build.gradle + version catalog）
├── decompile.sh          # 统一反编译模块（jadx > CFR > Fernflower）
├── cmd-find-source.sh    # find-source 命令
├── cmd-find-class.sh     # find-class 命令（索引 + 并行扫描）
├── cmd-index-all.sh      # index-all 全量索引（3 阶段并行）
├── cmd-utils.sh          # search/tree/list/rebuild/clean/init
├── _scan-jar-worker.sh   # Phase 1 并行工作线程
└── fetch-decompilers.sh  # 下载内置 CFR + Fernflower
```

## License

MIT
