# D1 签名操作清单（明早 09:20，约 15 分钟，全程唯一需要你的账号操作）

## 你要做的（GUI 方式，推荐）

1. 手机插电脑、保持亮屏（首次会弹"是否允许 USB 调试"，勾选一律允许）。
2. 打开 DevEco Studio → 打开工程 `D:\Projects\ReadestOhos`。
3. 菜单 **File → Project Structure → Signing Configs**。
4. 勾选 **Automatically generate signature（自动生成签名）**。
5. 弹出华为账号登录 → 用你的账号登录并确认。
6. 等待证书/Profile 生成完成（底部进度条，约 1–2 分钟），点 **OK**。
   - 成功标志：Signing Configs 界面出现 debug 证书信息，无红色报错；
   - `build-profile.json5` 里 `signingConfigs` 从 `[]` 变成含 material 的配置。
7. 完成后告诉我一声即可，剩下的构建、安装、启动全部我来。

## 之后的流程（全自动，我来跑）

```
scripts/deploy.sh          # 构建→安装→启动 一条命令
scripts/observe.sh         # 截图→OCR 读屏 + hilog 抓日志（观测闭环）
```

## 排查备忘

- 若提示"设备未连接"：手机上重新弹出的调试授权点允许；`hdc list targets` 应显示设备序列号而非 `[Empty]`。
- 若证书生成失败：多为账号未实名/网络问题，换手机热点重试。
- 手工签名（不推荐，仅 IDE 自动签名失败时备用）：材料结构与示例见 `build-profile.signing.example.json5`，密码为 IDE 加密串，不可手填。
