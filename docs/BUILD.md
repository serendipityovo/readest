# BUILD.md — 构建配方（D10.5 编写，D15 定稿）

> 从零到 HAP 的完整构建链。所有命令以 `D:\Projects\ReadestOhos` 为 cwd（bash）。

## 0. 前置依赖（本机已就位的位置）

| 依赖 | 位置 |
|---|---|
| DevEco Studio 26.0.0.851（SDK API 26 + hvigor + hdc + ohpm） | `E:\DevEco Studio` |
| JBR（hvigor 需要的 JDK） | `E:\DevEco Studio\jbr` |
| readest 前端源码（含 8 个 submodule） | `D:\Projects\readest` |
| Node/pnpm（前端构建；机器已有） | PATH |
| Python 3（打包注入/lab server） | PATH |

## 1. 前端构建（readest 侧，仅前端改动时需要）

```bash
cd /d/Projects/readest/apps/readest-app
NEXT_PUBLIC_APP_PLATFORM=tauri pnpm build   # 产出 out/（Next 静态导出）
```

## 2. 前端打包进壳工程（166MB→43MB + shim 注入）

```bash
bash /d/Projects/ReadestOhos/package_frontend.sh
```
步骤：拷贝 out/ → 去 sourcemap → 装 tauri_shim.js → 装 pdfjs vendor（cmaps/standard_fonts/wasm，fake-worker 必需）→ **index.html 注入 shim 标签 + `__TAURI_INTERNALS__.metadata` pre-script 兜底（KI-5 防御）** → 写 buildstamp（驱动设备端增量解包）。

## 3. HAP 构建（编译门）

```bash
export PATH="/e/DevEco Studio/jbr/bin:$PATH"
export JAVA_HOME="E:\\DevEco Studio\\jbr"
export DEVECO_SDK_HOME="E:\\DevEco Studio\\sdk"
"/e/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleHap --mode module -p product=default --no-daemon
```
产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（约 43.7MB）。
警告基线：54 条豁免（53 may-throw 提醒——捕获边界统一在 invoke 层；1 相册 user_grant 权限提醒）。**零 ERROR；deprecated 类警告须消解**（D10 已清 getContext×3）。

## 4. 安装与启动

```bash
HDC="/e/DevEco Studio/sdk/default/openharmony/toolchains/hdc"
"$HDC" install -r "D:\\...\\entry-default-unsigned.hap"   # 模拟器可装未签名；真机需签名（见 SIGNING.md）
"$HDC" shell "aa start -b com.yueyi.app -a EntryAbility"
# 桥接自测页直达（D11 冒烟入口）：
"$HDC" shell "aa start -b com.yueyi.app -a EntryAbility --ps selftest 1"
```

## 5. 一条龙

```bash
bash scripts/deploy.sh    # 构建→安装→启动
bash scripts/observe.sh   # 截图 + hilog 抓取
```

## 6. 签名（D11 起真机）

GUI 自动签名（用户 15 分钟）：见 SIGNING.md。签名后 `signingConfigs` 写入 build-profile.json5，构建自动出签名包。

## 7. 实验室（web 层验证，独立于设备）

```bash
bash scripts/lab_up.sh          # http://127.0.0.1:8931（www + mock_bridge + shim）
bash scripts/regression_v3.sh   # 七探针全回归（boot/reader/turso/opds_fail/http/tts/opds）
```

## 8. 模拟器

```bash
cd "/e/DevEco Studio/tools/emulator"   # 后台常驻运行（前台 timeout 会连带杀实例）
./Emulator.exe -start phone26 -instancePath "D:/emu-inst" -imageRoot "D:/emu-image" -hdcport 15555
# 镜像在 D:/emu-image/system-image/（中文用户名路径 qemu 打不开，已迁移）；hdc tconn 127.0.0.1:15555
# 解锁：power-shell wakeup + uinput -T -m 660 2100 660 200 120
```

## 9. 常见坑（实证记录）

- hvigor 需要 JBR 的 JAVA_HOME（系统 JDK 不行）
- 中文用户名路径：模拟器镜像必须放 ASCII 路径；构建产物路径含中文无碍
- `git rm -r --cached . -q` 的 `-q` 在 pathspec 后会被当路径参数——放前面
- lab_server SSL 偶发证书验证失败（老进程）→ 重启 lab_up.sh 即愈
- 增量构建会跳过 CompileArkTS（看不到警告全量）→ clean 构建复查警告
