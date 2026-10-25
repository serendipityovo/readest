# 1:1 复刻度审计报告（交付版 · 2026-10-23）

> 方法：前端 bundle 全调用面提取（317 个 invoke 命令）× NativeBridge/shim 实现对照 × 真机运行时 census（51 命令实调日志）三向交叉。

## 结论：核心阅读功能 1:1；平台专属功能按"原版在该平台也降级"或"华为生态等价物"原则处理

| 分级 | 数量 | 说明 |
|---|---|---|
| 真实现（真机验证） | 134 case | fs 26 命令全量、turso、tts 18、websocket、http、深链、picker、剪贴板、asset 密钥链、传感器、窗口/安全区等 |
| 形状应答（优雅降级） | ~40 | 返回契约形状的 no-op/空应答（widget/iap/eink/lookup 等） |
| 平台无关（原版 Windows 桌面同样没有） | ~30 | sign-in-with-apple、icloud、carplay、boox 笔、eink、haptics、biometric、macOS traffic lights、CLI 集成 |
| JS 回退已验证（原版 Rust 加速器的等价路径） | 8 | parse_epub/mobi/pdf_metadata、render_pdf_cover 等——**D14 十格式全绿证明 JS 解析链完整** |
| 明确降级（文档化增强项） | ~15 | localsend LAN 传书（11 命令）、内置浏览器（5）、shell 集成、updater、menu 栏、oauth start |

## 交付审计当日修复（真机复验通过）

1. **show_file_picker select() 永挂**：无参构造 DocumentViewPicker 从 web 调用栈弹出后回调丢失 → 显式传 UIAbility context 修复 → **真实 picker→选打印测试.pdf→导入成功（书架 11 本）**
2. **plugin:opener|open_url 补齐**：书内外链经系统 want 打开浏览器（原版行为等价）
3. **plugin:sharekit share_text/share_file 补齐**：鸿蒙 PC 无系统分享面板，经系统粘贴板承载
4. **plugin:dialog open/save/message 补齐**：open 复用 show_file_picker、save 用 DocumentViewPicker.save
5. SelfTest 回归：60/64 + 4 SKIP（零回归）

## 与原版 readest（桌面）的功能对照明细

**完全一致（真机验证）**：书库管理（导入/分组/排序/搜索）、阅读器（EPUB/MOBI/AZW3/PDF/TXT 全格式含 GBK/竖排）、进度记忆（epubcfi 落盘+重启恢复）、书签/标注/高亮（turso DB）、TTS 听书（HiAI 离线引擎，原版 Edge 在线）、OPDS 书城、字典/翻译、主题/字体/排版设置、剪贴板引文、深链/文件关联（file:// want）、快捷键、中英双语。
**等价实现**：文件选择器（DocumentViewPicker）、窗口管理（ArkUI 单窗+新窗口）、持久化（relationalStore≈SQLite）、密钥链（asset kit）。
**原版也无（桌面平台）**：生物认证、震动、Apple/CarPlay/Boox/iCloud 生态件。
**已知降级（后续增强）**：localsend LAN 直传（原版有）、内置网页浏览器（原版桌面有）、自动更新器（已答 is_updater_disabled 使前端优雅隐藏）、原生 Rust 解析加速（JS 回退，大书性能差——KI-6）。
**环境相关（非代码问题）**：外网 https（<local-proxy> TLS 拦截，rport 明文正常）、Edge 在线 TTS（同因）。

## 运行时证据
- 真机 census：51 命令实调，除环境类（fetch_send/download 外网）外全部 resolve ok
- 曾 resolve false 的 4 个均为调试期瞬态或已修（fs|open 协议组修复后 open×51 零失败）
