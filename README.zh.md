# zhc-android-lib-reader

> 让 AI Agent 像 Android Studio 一样直接阅读 Gradle 依赖的库源码。

[English Version](README.md)

---

## ✨ 功能特性

- **按类名读源码** — 给出类名（如 `Gson` 或 `com.google.gson.Gson`），自动定位并提取源码
- **按 Maven 坐标读源码** — 给出坐标（如 `com.google.code.gson:gson:2.11.0`），提取整个库
- **搜索库源码** — 在已提取的库源码中搜索关键词
- **列出库目录结构** — 查看库的包结构和文件列表
- **项目版本自动匹配** — 自动从项目 `build.gradle` 中解析实际使用的库版本
- **跨会话缓存** — 提取结果持久化，不会随对话结束消失
- **二分查找索引** — 类名查找仅需 **0.002s**，基于排序文件 + `look` 命令

## 🚀 快速开始

### 前置条件

- macOS / Linux
- `bash`、`unzip`、`find`
- Android 项目已同步过 Gradle（`~/.gradle/caches/` 中有缓存）
- 可选：[jadx](https://github.com/skylot/jadx)（用于反编译无源码的库，缺失时自动通过 `brew install jadx` 安装）

### 安装

```bash
# 1. 克隆仓库
git clone git@github.com:jaxtonzhc/zhc-android-lib-reader.git
cd zhc-android-lib-reader

# 2. 一键安装到所有 AI Agent（Cursor、Codex、Claude Code 等）
bash install.sh

# 3. 初始化并建立索引
./scripts/lib-reader.sh init
./scripts/lib-reader.sh index-all
```

`install.sh` 会自动检测并创建软链接到 `~/.cursor/skills/`、`~/.codex/skills/`、`~/.claude/skills/`、`~/.agents/skills/`、`~/.hermes/skills/`。

也可以手动安装：

```bash
ln -sf /path/to/zhc-android-lib-reader ~/.cursor/skills/zhc-android-lib-reader
```

## 📖 使用方法

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
# 首次使用：检查环境并建立索引
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

## 🔍 find-class 查找策略

### 第一步：索引查找（O(log n)，~0.002s）

使用 `look` 命令对排序后的 `class-lookup.txt` 进行二分查找。支持精确匹配（`com.google.gson.Gson`）和简单类名模糊匹配（`Gson`）。

### 第二步：Source JAR 直接提取

大多数开源库在 Maven 仓库发布时包含 `-sources.jar`，Gradle 同步时已下载到本地缓存，直接提取即可——无需反编译。

### 第三步：反编译 JAR/AAR（降级方案）

当 source JAR 不存在时，工具通过 **降级链** 自动从 3 个反编译器中选择来反编译 `.jar` 或 `.aar` 中的 `classes.jar`：

| 优先级 | 反编译器 | 安装方式 | 说明 |
|--------|---------|---------|------|
| 1 | [jadx](https://github.com/skylot/jadx) | `brew install jadx` | 质量最高；失败即终止（不降级） |
| 2 | [CFR](https://www.benf.org/other/cfr/) | `bash scripts/fetch-decompilers.sh` | 对复杂泛型和混淆代码处理稳健 |
| 3 | Fernflower | `bash scripts/fetch-decompilers.sh` | IntelliJ 内置反编译器，可读性好 |

**降级行为**：jadx 失败不会降级。CFR 和 Fernflower 互相自动降级——如果一个没有产出，自动尝试另一个。不绑定 Java 版本，纯按可用性选择。

### 第四步：Gradle 按需下载源码

当 Gradle 缓存中没有 source JAR 时，触发 Gradle 任务下载。

## 📁 缓存结构

```
~/.gradle/android-lib-reader/
├── sources/              # 源码提取结果
│   └── <groupId>/<artifactId>/<version>/
├── decompiled/           # 反编译结果（jadx）
│   └── <groupId>/<artifactId>/<version>/
├── index.json            # 库坐标 → 缓存路径
├── class-index.txt       # 倒排索引（库→类列表）
└── class-lookup.txt      # 排序查找文件（类→库，用于二分查找）
```

### 索引文件说明

- **`class-index.txt`** — 写优化的倒排索引，按库坐标分组，以 `##########` 分隔
- **`class-lookup.txt`** — 读优化的排序文件，每行 `类名\t库坐标`，按类名去重，供 `look` 二分查找

## 🏗 脚本架构

```
scripts/
├── lib-reader.sh         # 入口 + 命令路由（100 行）
├── common.sh             # 全局变量 + 基础工具
├── cache-ops.sh          # 索引读写操作
├── version.sh            # 项目版本自动解析
├── cmd-find-source.sh    # find-source 命令
├── cmd-find-class.sh     # find-class 命令
├── cmd-index-all.sh      # index-all 全量索引
└── cmd-utils.sh          # search/tree/list/rebuild/clean/init
```

## 📝 License

MIT
