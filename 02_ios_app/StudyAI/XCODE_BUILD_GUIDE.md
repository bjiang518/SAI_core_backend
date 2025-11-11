# Xcode 构建和测试指南

## ✅ 已修复的问题

### 1. 访问权限错误
**问题：** `PomodoroNotificationService` 的 action identifier 属性是 private，但 `PomodoroDeepLinkHandler` 需要访问它们。

**修复：** 已将以下属性从 `private` 改为 `internal`（默认访问级别）：
- `notificationCategoryIdentifier`
- `startActionIdentifier`
- `snoozeActionIdentifier`

**文件：** `PomodoroNotificationService.swift` (第20-22行)

---

## 🔨 在 Xcode 中构建项目

### 步骤 1：打开项目
```
打开 Xcode
File → Open → 选择：
/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI.xcodeproj
```

### 步骤 2：选择目标设备
```
在顶部工具栏选择：
StudyAI > iPhone 15 (或任何iOS 15.0+的模拟器)
```

### 步骤 3：清理构建
```
Product → Clean Build Folder (Cmd + Shift + K)
```

### 步骤 4：构建项目
```
Product → Build (Cmd + B)
```

### 步骤 5：检查构建输出
在Xcode左侧的 **Issue Navigator** (⚠️ 图标) 中查看：
- ✅ 绿色 = 构建成功
- ❌ 红色 = 有错误
- ⚠️ 黄色 = 警告（可忽略）

---

## 🔍 可能的编译问题和解决方案

### 问题 1：找不到 `PomodoroCalendarEvent`
**错误信息：**
```
Cannot find 'PomodoroCalendarEvent' in scope
```

**解决方案：**
1. 检查文件是否在 Target Membership 中
2. 在 Project Navigator 中选择 `PomodoroCalendarEvent.swift`
3. 在右侧 File Inspector 中确认勾选了 `StudyAI` target

### 问题 2：EventKit 权限描述缺失
**错误信息：**
```
This app has crashed because it attempted to access privacy-sensitive data without a usage description
```

**解决方案：**
- ✅ 已添加到 `Info.plist`
- 检查是否有以下键：
  - `NSCalendarsUsageDescription`
  - `NSCalendarsFullAccessUsageDescription`
  - `NSRemindersUsageDescription`

### 问题 3：Deep Link URL Scheme 未配置
**解决方案：**
- ✅ 已添加到 `Info.plist`
- 验证 `CFBundleURLTypes` 包含 `studyai` scheme

### 问题 4：Missing @EnvironmentObject
**错误信息：**
```
Missing argument for parameter 'deepLinkHandler' in call
```

**解决方案：**
- ✅ 已在 `StudyAIApp.swift` 中添加 `.environmentObject(deepLinkHandler)`
- 确保从 `ContentView` 导航到 `FocusView` 时继承了环境对象

---

## 🧪 测试新功能

### 1. 测试 25 分钟倒计时
```
步骤：
1. 运行 App (Cmd + R)
2. 导航到 "番茄专注" (Focus Mode)
3. 点击 "开始"
4. 验证：
   ✅ 显示 25:00 倒计时
   ✅ 每秒递减
   ✅ 进度环从满到空
```

### 2. 测试日历集成
```
步骤：
1. 点击顶部 "📅 日历" 按钮
2. 授权日历访问权限（首次）
3. 验证：
   ✅ 显示今天的日历事件
   ✅ 显示空闲时间推荐
   ✅ 可以添加番茄专注事件
```

### 3. 测试深度专注模式
```
步骤：
1. 在开始前开启 "🌙 深度专注模式" 开关
2. 点击 "开始"
3. 验证：
   ✅ 显示 "深度专注模式已启用" 横幅
   ✅ 屏幕亮度降低
   ✅ 提示启用系统勿扰模式
4. 点击横幅上的 ✕ 按钮
5. 验证：
   ✅ 深度专注模式关闭
   ✅ 亮度恢复
   ✅ 计时器继续运行
```

### 4. 测试通知提醒
```
步骤：
1. 打开日历，添加一个 2 分钟后开始的番茄专注
2. 等待（模拟器中可能需要手动触发）
3. 验证：
   ✅ 收到通知
   ✅ 通知有 "立即开始" 和 "5分钟后提醒" 按钮
```

### 5. 测试 Deep Link 跳转
```
步骤：
1. 点击通知的 "立即开始" 按钮
2. 验证：
   ✅ App 打开
   ✅ 自动跳转到番茄专注页面
   ✅ 自动开始倒计时
```

---

## 📊 构建输出分析

### 成功的构建输出
```
Build Succeeded
▸ Compiling PomodoroCalendarEvent.swift
▸ Compiling PomodoroCalendarService.swift
▸ Compiling PomodoroNotificationService.swift
▸ Compiling PomodoroDeepLinkHandler.swift
▸ Compiling DeepFocusService.swift
▸ Compiling PomodoroCalendarView.swift
▸ Linking StudyAI
▸ Signing StudyAI
```

### 如果有错误
1. **点击错误信息** - Xcode 会跳转到出错的代码行
2. **读取错误描述** - Xcode 会给出详细的错误原因
3. **修复代码**
4. **重新构建** (Cmd + B)

---

## 🚀 运行 App

### 在模拟器中运行
```
1. 选择目标：iPhone 15 (或任何 iOS 15.0+ 模拟器)
2. Product → Run (Cmd + R)
3. 等待模拟器启动和 App 安装
4. App 自动打开
```

### 在真机上运行
```
1. 连接 iPhone
2. 信任电脑（首次）
3. 在 Xcode 中选择你的设备
4. 可能需要配置签名：
   - Project Settings → Signing & Capabilities
   - 选择你的 Team
5. Product → Run (Cmd + R)
```

---

## 🐛 调试技巧

### 查看控制台日志
```
View → Debug Area → Activate Console (Cmd + Shift + Y)

查找关键日志：
- 🍅 "Pomodoro session started: 25:00"
- 📅 "Calendar access granted"
- 🔔 "Notification scheduled"
- 🔇 "Deep Focus Mode enabled"
- 🔗 "Handling deep link"
```

### 使用断点
```
1. 在代码行号左侧点击，设置断点
2. 运行 App
3. 当执行到断点时暂停
4. 检查变量值
5. 按 Continue (Cmd + Ctrl + Y) 继续
```

### 测试通知
```
模拟器中测试通知：
1. 打开模拟器的 Settings
2. Notifications → StudyAI → 允许通知
3. 在 App 中触发通知
4. 查看通知是否显示
```

---

## 📋 检查清单

构建前检查：
- [ ] 所有新文件都已添加到 Xcode 项目
- [ ] 所有文件都勾选了正确的 Target
- [ ] Info.plist 权限已配置
- [ ] 清理了构建文件夹

构建成功后检查：
- [ ] 没有编译错误（红色）
- [ ] 警告可以接受（黄色）
- [ ] App 可以正常启动
- [ ] 导航到番茄专注页面

功能测试检查：
- [ ] 25分钟倒计时正常工作
- [ ] 日历按钮可以打开日历界面
- [ ] 深度专注模式开关可以切换
- [ ] 音乐播放正常
- [ ] 完成后显示树木奖励

---

## 💡 提示

### 快捷键
- `Cmd + B` - 构建
- `Cmd + R` - 运行
- `Cmd + .` - 停止运行
- `Cmd + Shift + K` - 清理构建
- `Cmd + Shift + Y` - 显示/隐藏控制台
- `Cmd + 0` - 显示/隐藏导航器
- `Cmd + /` - 注释/取消注释代码

### 常见快速修复
- 点击错误旁边的 🔴 图标
- 选择 "Fix" 让 Xcode 自动修复
- 或查看建议的解决方案

---

## 📞 如果遇到问题

### 1. 清理并重新构建
```
Product → Clean Build Folder (Cmd + Shift + K)
Product → Build (Cmd + B)
```

### 2. 重启 Xcode
```
关闭 Xcode
重新打开项目
```

### 3. 删除 DerivedData
```
Xcode → Preferences → Locations
点击 DerivedData 路径旁的箭头
删除 StudyAI 相关文件夹
重新构建
```

### 4. 检查 Xcode 版本
```
确保使用 Xcode 14.0+
支持 iOS 15.0+ 的开发
```

---

## ✅ 预期结果

构建成功后，你应该看到：
1. ✅ Build Succeeded 消息
2. ✅ App 在模拟器中启动
3. ✅ 可以导航到番茄专注页面
4. ✅ 所有新功能按钮都显示正确
5. ✅ 没有崩溃或运行时错误

---

**最后更新：** 2025年11月6日
**Xcode 版本要求：** 14.0+
**iOS 版本要求：** 15.0+
