# ARCHITECTURE.md — 解析层与运行时架构决断（D6 · 2026-10-17）

> D6 决断门产物。依据：cargo check 实测（aarch64-unknown-linux-ohos，--no-default-features）
> × D1–D5 浏览器实验室五天全链实证 × 依赖树逆向（cargo tree -i）。

## 决断：B 计划 — 不把 Rust 主进程编入 OHOS 应用，全部功能由「前端 + ArkTS 桥」承载

### 依据一：Rust 路径的实测代价（cargo check 数据）

```
cargo check --target aarch64-unknown-linux-ohos --no-default-features -p Readest
→ 唯一编译错误：glib-sys v0.18.1（pkg-config 无法交叉）
依赖链：tauri(fork) → muda v0.19.3(菜单/托盘库) → gtk v0.18 → atk/glib/cairo 全家
```

- cairo 并非直接依赖，而是经 tauri 的 muda→gtk 链进入；OHOS sysroot **无 glib/gtk 系统库**，
  即使强行配置交叉 pkg-config，链接期也无库可链。
- 穿透该墙需要：① 改 tauri fork（packages/tauri）为 ohos 加 cfg 把 muda 剔除或 stub；
  ② 为 tauri 提供 ohos runtime（社区 ohos_tauri 移植或自写 runtime-less 壳）；
  ③ NAPI/cdylib 绑定层；④ 此后每轮上游同步都要重做补丁。**估算 ≥3 个工作日且引入长期维护面。**

### 依据二：B 计划已被五天 lab 实证为完整等价（对照表）

| Rust 侧能力 | B 计划等价物 | lab 实证状态 |
|---|---|---|
| fs/path 插件 | NativeBridge.ets（fileIo 沙箱）43 命令 | ✅ D2 全覆盖 census |
| turso/SQLite | NativeDatabase.ets（relationalStore 直通+标记文件） | ✅ D3 真实迁移链 |
| EPUB 解析/渲染 | foliate-js（前端自带） | ✅ D4 紅樓夢 1600 页/目录/翻页 |
| PDF 解析 | pdf.js fake-worker 主线程模式（vendor+MIME 已修） | ✅ D6 前置 A3 |
| 搜索/标注/进度 | 前端自包含 + config.json/booknotes | ✅ D5 |
| HTTP/网络 | D8 NetworkKit（计划内） | ⏳ |
| TTS | D7 Core Speech Kit（计划内） | ⏳ |

**结论：Rust 主进程在 OHOS 端没有不可替代的功能残留；其收益仅剩性能余量与上游对齐度，
不足以覆盖 ≥3 天代价 + 长期补丁维护面。**

### 生效架构（三层）

```
ArkUI 壳（Index.ets）
  └─ ArkWeb（http://readest.local 虚拟主机）
       └─ readest 前端 + tauri_shim.js（invoke/事件/convertFileSrc 伪装层）
            └─ window.__ohosBridge → NativeBridge.ets（43+ 命令分发）
                 ├─ fileIo / relationalStore / Asset Kit / window Kit ...
                 └─ 预留 D7：Core Speech / pasteboard / Share Kit
静态资源与内部主机：RawFileServer（readest.local / readest.ohos.internal[+asset/ 前缀]
/rangefile.localhost[查询区间协议] / 深路由 .html 兄弟解析 / pdfjs vendor）
```

### 重启 Rust 路径的条件（记录给未来，非本工期内）

上游 readest 若出现 JS 层无法等价的能力（如重型解析性能优化、Rust 独占格式），
且 ohos_tauri 社区 runtime 成熟到可直用 muda-free 配置时，再评估。入口：
`.cargo/config.toml`（已配 NDK linker）+ `--no-default-features -p Readest`。

## 附：D6 前置行动项落地记录（同日完成）

- A1 设备端 `/asset/<encoded>` 封面前缀剥离（RawFileServer）✅ 构建绿
- A2 `copy_uri_to_path`（{uri,dst}→{success,error}，file:// 剥壳 + 沙箱守卫）✅ 构建绿
- A3 PDF lab 预开 ✅ —— 抓出并修复两个跨端 bug：
  ① 打包链缺 `vendor/pdfjs`（out/ 不含 public/vendor）→ package_frontend.sh 增补拷贝（hap 38→43.5MB）
  ② `.mjs` MIME（lab_server extensions_map + 设备端 mimeOf 双修，模块导入拒收 text/plain）
- A4 语料 8 本：EPUB×5 + MOBI + AZW3 候选 + 含中文 PDF（Edge 无头打印自制）
- 回归 v2 双 PASS；hap 43.5MB 未签名候选
