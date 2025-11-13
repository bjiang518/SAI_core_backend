# iOS 集成检查清单

## ✅ 需要完成的步骤

### 1. 将新文件添加到 Xcode 项目

打开 Xcode 项目，将以下文件添加到项目中：

```bash
02_ios_app/StudyAI/StudyAI/Services/
├── AssistantLogger.swift  # 新文件 ⚠️ 需要添加
└── NetworkService+PracticeGenerator.swift  # 新文件 ⚠️ 需要添加
```

**操作步骤**:
1. 在 Xcode 中右键点击 `StudyAI/Services` 文件夹
2. 选择 "Add Files to StudyAI..."
3. 选择这两个文件
4. 确保勾选 "Copy items if needed"
5. Target 选择 "StudyAI"

### 2. 检查 NetworkService.swift 是否需要更新

`NetworkService+PracticeGenerator.swift` 是一个扩展，**理论上不需要修改主文件**。

但需要验证:
- NetworkService 有 `authService` 属性
- NetworkService 有 `baseURL` 属性
- 有 `NetworkError` 枚举定义

### 3. 更新 Info.plist（如果需要）

如果你的应用还没有网络权限配置，添加：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>sai-backend-production.up.railway.app</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <true/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
        </dict>
    </dict>
</dict>
```

### 4. 测试调用（示例 View）

创建一个测试视图来验证集成：

```swift
// TestPracticeGeneratorView.swift
import SwiftUI

struct TestPracticeGeneratorView: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var questions: [PracticeQuestion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("生成题目中...")
            } else if !questions.isEmpty {
                List(questions) { question in
                    VStack(alignment: .leading) {
                        Text(question.question)
                            .font(.headline)
                        Text("难度: \(question.difficulty)/5")
                            .font(.caption)
                        Text("类型: \(question.questionType)")
                            .font(.caption)
                    }
                }
            } else {
                Text("点击按钮生成测试题目")
            }

            Button("生成数学题目") {
                Task {
                    await testGeneration()
                }
            }
            .buttonStyle(.borderedProminent)

            if let error = errorMessage {
                Text("错误: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .navigationTitle("测试 Practice Generator")
    }

    func testGeneration() async {
        isLoading = true
        errorMessage = nil

        do {
            questions = try await networkService.generatePracticeQuestions(
                subject: "Mathematics",
                topic: "Quadratic Equations",
                count: 3,
                language: "en"
            )
            print("✅ 成功生成 \(questions.count) 个问题")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ 错误:", error)
        }

        isLoading = false
    }
}
```

### 5. 查看 AssistantLogger 数据

运行后，检查日志数据：

```swift
// 在任何地方调用
let stats = AssistantLogger.shared.getPerformanceStats()
print("请求数:", stats.requestCount)
print("成功率:", stats.successRate)
print("平均延迟:", stats.avgLatency)
print("P95 延迟:", stats.p95Latency)
print("总成本:", stats.totalCost)

// A/B 测试对比
if let comparison = AssistantLogger.shared.getABTestComparison() {
    print("Assistants API 平均延迟:", comparison.assistantsAPI.avgLatency)
    print("AI Engine 平均延迟:", comparison.aiEngine.avgLatency)
    print("延迟改善:", comparison.improvement.latencyReduction, "%")
}
```

---

## 🔧 可能需要的修改

### NetworkService.swift 需要的属性

确保你的 `NetworkService` 类有这些属性：

```swift
class NetworkService: ObservableObject {
    static let shared = NetworkService()

    let baseURL = "https://sai-backend-production.up.railway.app"  // ✅ 需要这个
    let authService: AuthenticationService  // ✅ 需要这个

    // ... 其他代码
}
```

### NetworkError 枚举定义

如果没有，添加：

```swift
enum NetworkError: Error {
    case invalidURL
    case unauthorized
    case invalidResponse
    case serverError(statusCode: Int)
    case decodingError(Error)
}
```

---

## ✅ 完成后的验证

1. **编译检查**: Cmd+B - 应该无错误
2. **运行应用**: Cmd+R
3. **测试功能**: 调用 `generatePracticeQuestions()`
4. **查看日志**: 检查 Xcode Console 输出
5. **查看 Logger**: 检查 `AssistantLogger.shared.recentMetrics`

---

## 📊 预期输出

成功调用后，你应该看到：

```
✅ 成功生成 3 个问题
[AssistantPerformance] [practice_generator] /api/ai/generate-questions/practice
Latency: 2.45s
Tokens: 150 in / 800 out
Cost: $0.0126
Success: true
API: AI Engine
```

（注意：初始时 `API: AI Engine`，因为 `USE_ASSISTANTS_API=false`）

---

## 🚨 常见问题

### 问题 1: 编译错误 - "Cannot find 'NetworkService' in scope"

**解决**: 确保新文件已添加到 Xcode target

### 问题 2: 运行时错误 - "baseURL not found"

**解决**: 在 `NetworkService.swift` 中添加 `baseURL` 属性

### 问题 3: 401 Unauthorized

**解决**: 检查 `AuthenticationService` 的 token 是否有效

### 问题 4: 网络请求失败

**解决**:
1. 检查后端是否运行
2. 检查 URL 是否正确
3. 检查网络权限配置

---

现在你可以开始 iOS 集成了！
