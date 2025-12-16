# 🔍 Diagram Rendering Debug Guide - Xcode调试指南

## 问题描述
```
SWIFT TASK CONTINUATION MISUSE: renderSVG(_:hint:) leaked its continuation without resuming it
```

## Xcode调试步骤

### 1. 打开项目并设置断点

```bash
cd /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI
open StudyAI.xcodeproj
```

### 2. 关键断点位置 (DiagramRendererView.swift)

#### A. SVG渲染入口点
**文件**: `DiagramRendererView.swift`
**行号**: `290` (SVGRenderer.renderSVG函数开始)
```swift
func renderSVG(_ svgCode: String, hint: NetworkService.DiagramRenderingHint?) async throws -> UIImage {
    // 在这里设置断点 ⚡
    print("🎨 [SVGRenderer] Starting SVG rendering...")
```

#### B. Continuation创建点
**行号**: `297` (withCheckedThrowingContinuation开始)
```swift
return try await withCheckedThrowingContinuation { continuation in
    // 设置断点 - 检查continuation是否创建 ⚡
    DispatchQueue.main.async {
```

#### C. Continuation调用点
**行号**: `303` (SVGImageRenderer completion传递)
```swift
let renderer = SVGImageRenderer(
    svgCode: svgCode,
    hint: hint,
    completion: continuation.resume  // 断点 - 检查传递 ⚡
)
```

#### D. 完成状态检查点
**行号**: `636` (completeWithResult函数开始)
```swift
private func completeWithResult(image: UIImage?, error: Error?) {
    // 断点 - 检查是否被调用多次 ⚡
    guard !hasCompleted else {
        return
    }
    hasCompleted = true
```

#### E. WebView导航委托方法
**行号**: `804` (didFinish方法)
```swift
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // 断点 - 检查是否被调用 ⚡
    print("🎨 [SVGRenderer] === NAVIGATION: DID FINISH (SUCCESS) ===")
```

#### F. 超时处理
**行号**: `770` (handleTimeout函数)
```swift
private func handleTimeout() {
    // 断点 - 检查是否超时被触发 ⚡
    print("🎨 [SVGRenderer] === TIMEOUT HANDLER CALLED ===")
```

### 3. Xcode调试配置

#### A. 启用Runtime Issues检测
1. 在Xcode中: **Product > Scheme > Edit Scheme**
2. 选择 **Run** tab
3. 在 **Diagnostics** 部分启用:
   - ✅ **Thread Sanitizer** (检测并发问题)
   - ✅ **Main Thread Checker** (检测主线程违规)
   - ✅ **Address Sanitizer** (内存问题)

#### B. Swift Concurrency调试
在 **Environment Variables** 中添加:
```
SWIFT_TASK_ENQUEUE_GLOBAL_WITH_DELAY = 1
LIBDISPATCH_LOG = YES
```

#### C. Console日志过滤
在Xcode Console中设置过滤器:
```
🎨 [SVGRenderer]
🎨 [DiagramImage]
SWIFT TASK CONTINUATION
```

### 4. 调试检查清单

#### ✅ 第一次运行检查
1. **启动模拟器**: iPhone 15 Pro (推荐)
2. **运行应用**: Cmd+R
3. **触发diagram生成**:
   - 发送包含图形内容的消息
   - 点击"生成示意图"按钮
4. **观察Console输出**

#### ✅ 断点调试流程
1. **入口断点触发** → 检查SVG代码是否有效
2. **Continuation创建** → 确认continuation对象正常创建
3. **WebView设置** → 检查delegate是否正确设置
4. **导航开始** → 观察didStartProvisionalNavigation
5. **导航完成** → 确认didFinish被调用
6. **Completion调用** → 验证continuation.resume被调用

#### ✅ 问题诊断
- **如果didFinish未被调用**: WebView加载失败
- **如果completion被多次调用**: 重复resume导致crash
- **如果超时触发**: WebView卡住或HTML无效

### 5. 常见问题解决

#### 问题1: WebView导航从未开始
```swift
// 在renderSVGWithWebView函数中检查
print("WebView.navigationDelegate: \(webView?.navigationDelegate != nil)")
print("HTML content valid: \(htmlContent.count > 0)")
```

#### 问题2: 导航开始但从未完成
```swift
// 检查HTML内容是否有效
let svgValid = svgCode.lowercased().contains("<svg")
print("SVG tag present: \(svgValid)")
```

#### 问题3: Continuation被多次resume
```swift
// 在completeWithResult中添加调用栈打印
print("Completion called from: \(Thread.callStackSymbols.first ?? "unknown")")
```

### 6. 模拟器调试命令

```bash
# 重置模拟器 (清除缓存)
xcrun simctl erase "iPhone 15 Pro"

# 查看模拟器日志
xcrun simctl spawn booted log stream --predicate 'subsystem contains "com.studyai"'

# 检查WebKit进程
xcrun simctl spawn booted ps aux | grep -i webkit
```

### 7. 预期的正常日志流程

```
🎨 [SVGRenderer] === STARTING SVG WEBVIEW RENDERING ===
🎨 [SVGRenderer] ✅ Set navigation delegate BEFORE loading
🎨 [SVGRenderer] === HTML CONTENT ANALYSIS ===
🎨 [SVGRenderer] ✅ Valid SVG detected (contains <svg tag)
🎨 [SVGRenderer] === STARTING HTML LOAD OPERATION ===
🎨 [SVGRenderer] === NAVIGATION: DID START PROVISIONAL ===
🎨 [SVGRenderer] === NAVIGATION POLICY: ACTION ===
🎨 [SVGRenderer] === NAVIGATION POLICY: RESPONSE ===
🎨 [SVGRenderer] === NAVIGATION: DID COMMIT ===
🎨 [SVGRenderer] === NAVIGATION: DID FINISH (SUCCESS) ===
🎨 [SVGRenderer] === STARTING SNAPSHOT CAPTURE ===
🎨 [SVGRenderer] ✅ Snapshot captured successfully
🎨 [SVGRenderer] === COMPLETING RENDERING RESULT ===
🎨 [SVGRenderer] ✅ Success result
```

### 8. 失败情况的诊断

#### 如果看到超时:
```
🎨 [SVGRenderer] ⏰ Timeout timer fired after 3 seconds
🎨 [SVGRenderer] === ATTEMPTING ALTERNATIVE RENDERING ===
```
→ **问题**: WebView导航卡住，需要检查HTML/SVG内容

#### 如果看到process termination:
```
🎨 [SVGRenderer] === CRITICAL: WEB CONTENT PROCESS TERMINATED ===
```
→ **问题**: WebKit进程崩溃，可能是内存问题或无效HTML

#### 如果完全没有日志:
→ **问题**: DiagramRendererView未被创建或SVG路径未被触发

### 9. 快速测试用例

在SessionChatView中添加测试按钮:
```swift
Button("Test SVG") {
    // 直接创建DiagramRendererView进行测试
    let testSVG = "<svg width='200' height='200'><circle cx='100' cy='100' r='50' fill='blue'/></svg>"
    // 在这里设置断点测试
}
```

### 10. 下一步行动

1. **立即设置断点** → DiagramRendererView.swift:290, 297, 303, 636, 804
2. **运行调试** → 触发diagram生成功能
3. **观察断点触发顺序** → 确定哪个步骤失败
4. **检查日志输出** → 对比预期流程
5. **报告具体失败点** → 基于断点和日志确定根本原因

记住: Swift Task Continuation只能被resume一次，多次调用会导致crash！