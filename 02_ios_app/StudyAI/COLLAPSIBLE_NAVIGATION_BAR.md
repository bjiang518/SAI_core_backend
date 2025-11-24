# Collapsible Navigation Bar Implementation

## ✅ 已实现的功能

### 1. **可折叠 Navigation Bar**
- **折叠状态**：显示为左侧小圆点（50x50圆形按钮，liquid glass效果）
- **展开状态**：完整的navigation bar，包含返回按钮、标题和自定义trailing内容
- **流畅动画**：spring动画，响应时间0.5秒，阻尼系数0.75

### 2. **视觉设计**
- **Liquid Glass效果**：使用 `.ultraThinMaterial` 实现毛玻璃效果
- **折叠按钮图标**：三个水平小圆点（表示可展开）
- **收缩按钮图标**：`chevron.compact.left`（表示可收缩）
- **阴影效果**：轻微阴影增强层次感

### 3. **全局状态管理**
- `NavigationBarState.shared`：单例模式管理折叠/展开状态
- 所有页面共享同一个折叠状态
- 支持跨页面保持折叠状态

### 4. **触觉反馈**
- 展开时：中等强度震动（medium）
- 收缩时：轻度震动（light）
- 增强用户交互体验

## 📁 新增文件

### 1. `CollapsibleNavigationBar.swift`
**位置**：`StudyAI/Views/Components/CollapsibleNavigationBar.swift`

**内容**：
- `NavigationBarState`：全局状态管理器
- `CollapsibleNavigationBar`：可折叠navigation bar组件
- `ScaleButtonStyle`：按钮按压动画样式

### 2. `View+CollapsibleNavigation.swift`
**位置**：`StudyAI/Views/Components/View+CollapsibleNavigation.swift`

**内容**：
- View扩展，提供便捷的 `.collapsibleNavigationBar()` modifier
- `CollapsibleNavigationModifier`：SwiftUI modifier实现

## 🔧 在 Xcode 中添加新文件

**重要**：新创建的 Swift 文件需要手动添加到 Xcode 项目中：

1. 打开 `StudyAI.xcodeproj`
2. 在 Project Navigator 中找到 `StudyAI/Views/Components/` 目录
3. 右键点击 `Components` 文件夹 → `Add Files to "StudyAI"...`
4. 选择以下文件：
   - `CollapsibleNavigationBar.swift`
   - `View+CollapsibleNavigation.swift`
5. 确保勾选 "Copy items if needed" 和 "Add to targets: StudyAI"
6. 点击 `Add`

## 📝 使用方法

### 方法1：直接使用组件

```swift
import SwiftUI

struct MyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            // 主要内容
            ScrollView {
                VStack(spacing: 20) {
                    // 添加顶部spacer为navigation bar留出空间
                    Spacer()
                        .frame(height: 70)

                    // 你的内容
                    Text("Hello World")
                }
            }

            // 可折叠 navigation bar（覆盖在顶部）
            CollapsibleNavigationBar(
                title: "我的页面",
                showBackButton: true,
                onBack: {
                    dismiss()
                }
            ) {
                // Trailing内容（右侧按钮）
                Button(action: {}) {
                    Image(systemName: "gear")
                }
            }
            .zIndex(100)
        }
        .navigationBarHidden(true)
    }
}
```

### 方法2：访问全局状态

```swift
@StateObject private var navState = NavigationBarState.shared

// 手动控制折叠/展开
Button("折叠") {
    navState.collapse()
}

Button("展开") {
    navState.expand()
}

Button("切换") {
    navState.toggle()
}
```

## 🎨 设计细节

### 折叠状态（小圆点）
- **尺寸**：50x50 points
- **背景**：`.ultraThinMaterial`
- **图标**：3个水平小圆点（5x5）
- **阴影**：`radius: 8, opacity: 0.1`

### 展开状态（完整bar）
- **高度**：自适应内容（padding 12）
- **圆角**：25 points
- **背景**：`.ultraThinMaterial`
- **阴影**：`radius: 12, opacity: 0.08`

### 收缩按钮
- **尺寸**：32x32 points
- **背景**：`Color.primary.opacity(0.08)`
- **图标**：`chevron.compact.left`，16pt，semibold

### 返回按钮
- **尺寸**：32x32 points
- **背景**：`Color.primary.opacity(0.08)`
- **图标**：`chevron.left`，14pt，semibold

## ✨ 动画参数

```swift
// 展开/收缩动画
.spring(response: 0.5, dampingFraction: 0.75)

// 按钮按压动画
.spring(response: 0.3, dampingFraction: 0.6)

// Transition动画
.asymmetric(
    insertion: .scale(scale: 0.1, anchor: .leading).combined(with: .opacity),
    removal: .scale(scale: 0.1, anchor: .leading).combined(with: .opacity)
)
```

## 📋 已更新的页面

### 1. `DigitalHomeworkView.swift`
- ✅ 使用 CollapsibleNavigationBar
- ✅ 根据不同状态显示不同的trailing内容
- ✅ 添加顶部spacer（60-70 points）

### 2. `HomeworkSummaryView.swift`
- ✅ 使用 CollapsibleNavigationBar
- ✅ 简洁的返回按钮配置
- ✅ 添加顶部spacer（70 points）

## 🚀 其他页面如何集成

对于任何需要 navigation bar 的页面：

1. 隐藏默认 navigation bar：`.navigationBarHidden(true)`
2. 使用 ZStack 布局
3. 在顶部添加 `CollapsibleNavigationBar`
4. 在内容区域顶部添加 spacer（60-70 points）

**示例模板**：

```swift
struct AnyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            // 内容
            ScrollView {
                VStack {
                    Spacer().frame(height: 70)
                    // 你的内容
                }
            }

            // Navigation bar
            CollapsibleNavigationBar(
                title: "标题",
                showBackButton: true,
                onBack: { dismiss() }
            ) {
                // 右侧按钮
            }
            .zIndex(100)
        }
        .navigationBarHidden(true)
    }
}
```

## 🎯 优势

1. **节省屏幕空间**：折叠后释放70 points的垂直空间
2. **全局一致性**：所有页面共享折叠状态
3. **流畅动画**：spring动画提供自然的交互感
4. **易于集成**：简单的API，支持自定义内容
5. **视觉美观**：liquid glass效果符合iOS设计规范

## 🔍 故障排查

### 问题：按钮被 navigation bar 遮挡
**解决**：确保主内容区域顶部有足够的spacer

```swift
Spacer().frame(height: 70) // 或者根据折叠状态动态调整
```

### 问题：Navigation bar 不显示
**检查**：
1. 是否添加了 `.navigationBarHidden(true)`
2. 是否使用了 `.zIndex(100)`
3. 文件是否正确添加到 Xcode 项目

### 问题：动画不流畅
**优化**：确保所有状态更新都在 `withAnimation` 块内

```swift
withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
    navState.isCollapsed.toggle()
}
```

## 📱 测试建议

1. **滚动测试**：折叠后确认按钮不再被遮挡
2. **动画测试**：多次展开/收缩，检查动画流畅性
3. **跨页面测试**：在不同页面间导航，验证状态保持
4. **触觉反馈测试**：确认震动效果正常

## 🎉 完成状态

- ✅ 可折叠 navigation bar 组件
- ✅ Liquid glass 视觉效果
- ✅ 流畅的展开/收缩动画
- ✅ 全局状态管理
- ✅ 触觉反馈
- ✅ DigitalHomeworkView 集成
- ✅ HomeworkSummaryView 集成
- ✅ 使用文档

**下一步**：在 Xcode 中添加新文件并运行测试！
