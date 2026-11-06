/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { nativeBridge } from '../services/NativeBridge';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    hilog.error(DOMAIN, 'readestWant', 'onCreate want=%{public}s', JSON.stringify(want).slice(0, 400));
    // D9 文件关联：冷启动"打开方式"want（uri 暂存，前端监听就位后补投）
    try {
      nativeBridge.handleWant(want);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'handleWant failed: %{public}s', JSON.stringify(err));
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 单实例热启动：应用已运行时再次被文件打开拉起（want 沙箱化+双通道投递见
    // NativeBridge.handleWant V-16/V-17 修复）
    // V-18 备案：--ps selftest 1 仅 onWindowStageCreate 生效（冷启直达自测
    // 页）；热启动走本分支参数被忽略——复测请先 force-stop 再冷启拉起
    hilog.error(DOMAIN, 'readestWant', 'onNewWant want=%{public}s', JSON.stringify(want).slice(0, 400));
    try {
      nativeBridge.handleWant(want);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'handleWant failed: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    // 调试入口：aa start 带 --ps selftest 1 直达桥接自测页（D11 冒烟复用）
    let page: string = 'pages/Index';
    try {
      const flag: Object | undefined = this.launchWant?.parameters?.['selftest'];
      if (flag !== undefined && String(flag) === '1') {
        page = 'pages/SelfTest';
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'read selftest flag failed: %{public}s', JSON.stringify(err));
    }
    windowStage.loadContent(page, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content: %{public}s', page);
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}