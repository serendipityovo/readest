# 鸿蒙应用市场上架指南（readest-ohos · com.readest.app）

> 面向本项目当前状态写的操作手册。当前工程用的是**调试自动签名**（debug 证书/Profile），只能装机测试，**不能上架**——上架需要 AGC 的**发布（release）证书与 Profile**。

---

## 0. 前置条件（一次性）

| 项 | 要求 | 说明 |
|---|---|---|
| 华为开发者账号 | 已实名认证（个人或企业） | developer.huawei.com → 实名认证 |
| AppGallery Connect | 创建应用 | console.agconnect.huawei.com → 我的项目 → 创建 → 平台选 HarmonyOS（单一） |
| 包名 | `com.readest.app` | 创建应用时填写，**上架后不可改**；当前工程已用此名真机验证 |
| ICP 备案 | 中国区上架必须 | 2023 起国内应用分发需 APP 备案（AGC 内有备案入口，走华为云备案流程，约 1-2 周） |
| 软件著作权 | 部分类目需要 | 阅读类一般需软著或版权声明（开源项目可用许可证+仓库地址佐证） |
| 开源许可 | **AGPL-3.0 合规** | readest 上游是 AGPL-3.0：fork 发布必须**开源你的修改**并提供源码获取方式（应用内"关于"页放源码仓库链接是最稳妥做法），不可闭源上架 |

---

## 1. 申请发布证书与 Profile（AGC 控制台）

1. AGC → **证书、Profile 和 HAR 查看**（我的项目 → 常规 → HarmonyOS APP）：
   - **证书**：新建 → 类型选 **发布证书** → 下载 `.cer`；
   - **Profile**：新建 → 类型选 **发布 Profile** → 关联证书 → 勾选设备类型（phone/tablet/2in1，与 module.json5 的 deviceTypes 一致）→ 受益所有者选本应用 → 下载 `.p7b`；
   - **密钥库（.p12）**：DevEco 里 **Build → Generate Key and CSR** 生成专用发布密钥（**不要复用 debug 的 p12**），CSR 提交给上面第 1 步申请证书用。
2. 材料落位（建议）：
   ```
   D:\Projects\ReadestOhos\signing\
     release.p12    发布密钥库
     release.cer    发布证书
     release.p7b    发布 Profile
   ```
   ⚠️ p12 的密码**不要提交进 git**（build-profile 里用环境变量或本机文件注入，见下）。

## 2. 工程侧发布化改动（一次性）

### 2.1 build-profile.json5 增加 release 签名配置

在 `signingConfigs` 数组里追加（保留现有 debug 项）：

```json5
"signingConfigs": [
  /* …现有 default(debug)… */
  {
    "name": "release",
    "type": "HarmonyOS",
    "material": {
      "certpath": "D:/Projects/ReadestOhos/signing/release.cer",
      "storePassword": "00000019XXXXXXXXXXXXXXXX…",   // DevEco 打开工程后它会自动改写成加密串
      "keyAlias": "readest-release",
      "keyPassword": "00000019XXXXXXXXXXXXXXXX…",
      "profile": "D:/Projects/ReadestOhos/signing/release.p7b",
      "signAlg": "SHA256withECDSA",
      "storeFile": "D:/Projects/ReadestOhos/signing/release.p12"
    }
  }
]
```
然后把 `products.default.signingConfig` 指向 `"release"`（或在打包命令里用 `-p buildMode=release` 切换）。
> 明文密码只写一次：用 DevEco 打开工程保存后，IDE 会把密码字段替换为机器加密串（与现在 debug 配置里的 `00000019…` 形态相同）。此后这台机器命令行直签。

### 2.2 关闭调试通道（审核硬要求）

`entry/src/main/ets/pages/Index.ets` 第 24 行 `setWebDebuggingAccess(true)`：
```typescript
// 发布构建关闭 webview 远程调试（审核项）
if (debuggable) { webview.WebviewController.setWebDebuggingAccess(true); }
```
建议用 `build-profile.json5` 的 `debuggable`（debug 构建默认 true，release 为 false）或常量开关控制。

### 2.3 版本与元数据

- `AppScope/app.json5`：`versionCode` 递增（如 1000001），`versionName`（如 1.0.1）——每次上传新包必须比 AGC 已传版本高；
- `vendor`: 建议从 "example" 改为你的开发者名/团队名（审核会看）；
- 图标/名称：`AppScope/resources` 下 `layered_image` 与 `app_name`（当前 "Readest"）——确认无商标冲突风险；如需改名（如"某阅读器"）改 string 即可。

### 2.4 隐私合规（审核重点）

- **隐私政策 URL 必填**：需要一个可访问的网页（GitHub Pages 即可），声明：本地文件读写（导入书籍）、剪贴板（复制引文）、网络访问（OPDS 书城/TTS）、不采集个人数据（telemetry 可在设置关闭）；
- **权限用途**：当前只声明了 `ohos.permission.INTERNET`，用途写"在线书城/语音合成"；picker/剪贴板/传感器走系统受控 API 无需声明——保持最小权限是加分项；
- 应用内首次启动建议弹一次隐私确认（readest 前端已有 telemetry 询问弹窗，可复用）。

## 3. 构建上架包（.app）

上架包是 **APP 包（.app）**，不是装机用的 .hap：

```bash
cd /d/Projects/ReadestOhos
export PATH="/e/DevEco Studio/jbr/bin:$PATH"
export JAVA_HOME="E:\\DevEco Studio\\jbr"
export DEVECO_SDK_HOME="E:\\DevEco Studio\\sdk"
"/e/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleApp \
  --mode project -p product=default -p buildMode=release --no-daemon
```

- 产物：`build/app/outputs/default/readest-ohos-default-signed.app`（整包，含全部 HAP）；
- 提交前自检：`SignHap` 任务成功 + 用 `unzip -l xxx.app` 确认结构；
- **上架前装机回归**：把 .app 后缀改不了直接装，可用 `bm install` 装 release hap 或重新出 release 签名的 hap 装真机跑一遍 SelfTest（60/64 基线）——**发布证书签名包首次装机建议必测**。

## 4. AGC 上传与提审

1. AGC → 我的项目 → readest → **HarmonyOS 应用 → 版本管理**：
   - 软件包管理 → 上传 `.app`（校验签名/版本号/包名）；
   - 填版本说明（changelog）、发布范围（中国区/全局）；
2. **应用信息**：分类（阅读/图书），截图 3-5 张（3120×2080 真机截屏即可：书架/阅读页/竖排/TTS），应用介绍，年龄分级问卷；
3. **内容合规**：阅读器本身不含内容——审核问卷里注明"内容来自用户本地文件与用户自配 OPDS 源，应用不分发内容"；
4. **版权材料**：AGPL-3.0 许可证文本 + 源码仓库地址（开源声明）；若用软著走"著作权"材料；
5. 提交审核 → 常规 1-3 个工作日；驳回最常见原因：隐私政策缺失、截图与实际不符、调试开关未关、权限用途未说明。

## 5. 审核通过后

- 自动分发到应用市场（可在 AGC 设置分阶段放量 10%/50%/100%）；
- 升级流程：改 versionCode → 重出 .app → 上传新版本 → 提审（老用户自动收到更新）；
- **本工程签名材料与密码串永不入 git**（.gitignore 已含 signing/ 建议），泄露则去 AGC 吊销重发。

## 附：常见坑（本项目相关）

| 坑 | 说明 |
|---|---|
| debug 证书上架 | 直接被拒——AGC 校验 Profile 类型必须是 release |
| compatibleSdkVersion | 当前 "6.1.0(23)"，AGC 会要求 ≥ 最低上架 API（以提交时市场政策为准，过低会提示） |
| setWebDebuggingAccess | 未关闭属安全审核风险项 |
| 版本号不递增 | 上传报错 versionCode 冲突 |
| 备案未完成 | 中国区上架卡在最后一步（备案平均 1-2 周，提前办） |
| AGPL 闭源 | 法律风险 + 华为开源审核要求源码可得 |
