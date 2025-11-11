# 番茄园功能实现总结

## 更新时间
2025年11月6日

## 功能概述
将原来的"树木花园"改造为"番茄园"，用户完成专注后随机获得三种可爱番茄之一，更符合番茄工作法的主题。

---

## 🍅 三种可爱番茄

### 1. 经典番茄 (tmt1.png)
- **特点**: 简单可爱，红色番茄带绿色茎叶
- **描述**: 最经典的番茄，简单可爱
- **稀有度**: 普通

### 2. 卷藤番茄 (tmt2.png)
- **特点**: 带着卷曲藤蔓，活力十足
- **描述**: 带着卷曲藤蔓的番茄，活力十足
- **稀有度**: 普通

### 3. 萌萌番茄 (tmt3.png)
- **特点**: 粉嫩可爱，温柔贴心
- **描述**: 粉嫩可爱的番茄，温柔贴心
- **稀有度**: 普通

---

## ✅ 已实现的功能

### 1. 番茄类型模型 (TomatoType.swift)

**位置**: `/StudyAI/Models/TomatoType.swift`

**核心组件**:

#### TomatoType枚举
```swift
enum TomatoType: String, Codable, CaseIterable {
    case classic = "classic"    // 经典番茄
    case curly = "curly"        // 卷藤番茄
    case cute = "cute"          // 萌萌番茄

    // 显示名称、图片名称、描述
    var displayName: String
    var imageName: String
    var description: String

    // 随机获取
    static func random() -> TomatoType
}
```

#### Tomato结构体
```swift
struct Tomato: Identifiable, Codable {
    let id: String
    let type: TomatoType
    let earnedDate: Date
    let focusDuration: TimeInterval

    // 格式化专注时长和日期
    var formattedDuration: String
    var formattedDate: String
}
```

#### TomatoGardenStats结构体
```swift
struct TomatoGardenStats {
    var totalTomatoes: Int
    var totalFocusTime: TimeInterval
    var classicCount: Int
    var curlyCount: Int
    var cuteCount: Int
    var longestSession: TimeInterval
    var firstTomatoDate: Date?
}
```

---

### 2. 番茄园服务 (TomatoGardenService.swift)

**位置**: `/StudyAI/Services/TomatoGardenService.swift`

**核心功能**:

#### 添加番茄
```swift
func addTomato(from session: FocusSession) -> Tomato {
    // 随机选择番茄类型
    let tomatoType = TomatoType.random()

    // 创建番茄实例
    let tomato = Tomato(type: tomatoType, ...)

    // 保存并更新统计
    tomatoes.append(tomato)
    saveTomatoes()
    updateStats()

    return tomato
}
```

#### 数据持久化
- 使用UserDefaults保存
- JSON编码/解码
- 自动加载和保存

#### 统计功能
- 总番茄数量
- 总专注时间
- 各类型番茄数量
- 最长专注时长
- 今日/本周番茄

#### 成就系统
```swift
func checkAchievements() -> [String] {
    // 第一个番茄
    // 10、50、100个番茄里程碑
    // 集齐所有类型
}

func getNextMilestone() -> (count: Int, description: String)?
```

---

### 3. 番茄园视图 (TomatoGardenView.swift)

**位置**: `/StudyAI/Views/TomatoGardenView.swift`

**UI组件**:

#### 统计卡片
- 总番茄数
- 总专注时间
- 最长专注
- 各类型番茄分布

#### 筛选器
- 全部
- 今天
- 本周
- 按类型筛选（经典/卷藤/萌萌）

#### 番茄网格
- 3列网格布局
- 显示番茄图片
- 显示类型名称
- 显示专注时长和日期
- 长按删除功能

#### 里程碑卡片
- 显示下一个目标
- 进度环显示
- 还需要多少个番茄

---

### 4. 集成到专注流程

**修改的文件**: `FocusView.swift`

#### 更新的引用

**之前**:
```swift
@StateObject private var gardenService = FocusTreeGardenService.shared
@State private var showGarden = false
@State private var earnedTree: FocusTree?
```

**改为**:
```swift
@StateObject private var tomatoGarden = TomatoGardenService.shared
@State private var showTomatoGarden = false
@State private var earnedTomato: Tomato?
```

#### 顶部按钮
- 从"🌳 我的花园"改为"🍅 我的番茄园"
- 红色主题背景

#### 完成逻辑
```swift
private func endSession() {
    if let completedSession = focusService.endSession() {
        musicService.stop()

        // 添加番茄到番茄园
        let tomato = tomatoGarden.addTomato(from: completedSession)
        earnedTomato = tomato

        // 显示完成动画
        withAnimation {
            showCompletionAnimation = true
        }
    }
}
```

#### 完成动画
- 显示获得的番茄图片（150x150）
- 显示番茄类型和描述
- 显示专注时长和积分
- "🍅 查看我的番茄园"按钮

---

## 📁 新增文件清单

### Models
- ✅ `TomatoType.swift` - 番茄类型和数据模型

### Services
- ✅ `TomatoGardenService.swift` - 番茄园服务

### Views
- ✅ `TomatoGardenView.swift` - 番茄园UI

### 修改的文件
- ✅ `FocusView.swift` - 集成番茄园

---

## 🎨 UI设计

### 颜色主题
- **主色调**: 红色（番茄色）
- **按钮渐变**: 红色到半透明红色
- **图标**: 🍅 番茄emoji

### 布局
- **统计卡片**: 圆角16，阴影
- **番茄网格**: 3列，间距16
- **筛选器**: 横向滚动，圆角芯片

### 动画
- 完成时番茄放大动画（spring效果）
- 弹性缩放：0.5 → 1.0
- 阻尼：0.6

---

## 🚀 用户体验流程

### 完成专注 → 获得番茄

```
1. 用户开始25分钟专注
   ↓
2. 拖拽停止按钮到圆环内结束
   ↓
3. 系统随机选择一个番茄类型
   ↓
4. 弹出完成动画
   - 显示获得的番茄图片
   - 显示类型和描述
   - 显示专注时长和积分
   ↓
5. 用户点击"查看我的番茄园"
   ↓
6. 打开番茄园，看到新增的番茄
```

### 查看番茄园

```
1. 点击顶部🍅图标
   ↓
2. 查看统计信息
   - 总番茄数
   - 总专注时间
   - 各类型分布
   ↓
3. 使用筛选器
   - 按时间：全部/今天/本周
   - 按类型：经典/卷藤/萌萌
   ↓
4. 查看番茄网格
   - 每个番茄的详细信息
   - 长按删除
```

---

## 🔧 技术实现细节

### 随机算法
```swift
static func random() -> TomatoType {
    return TomatoType.allCases.randomElement() ?? .classic
}
```
- 使用`randomElement()`确保随机性
- 默认降级到经典番茄

### 数据持久化
```swift
private func saveTomatoes() {
    if let encoded = try? JSONEncoder().encode(tomatoes) {
        userDefaults.set(encoded, forKey: tomatoesKey)
    }
}

private func loadTomatoes() {
    if let data = userDefaults.data(forKey: tomatoesKey),
       let decoded = try? JSONDecoder().decode([Tomato].self, from: data) {
        tomatoes = decoded
    }
}
```

### 统计更新
- 自动计算总数量
- 自动分类统计
- 实时更新@Published属性

---

## 📋 待完成任务

### 1. 添加番茄图片到Xcode项目

**步骤**:

1. 打开Xcode项目
2. 找到或创建Assets目录
3. 添加三张图片：
   - `tmt1.png` → 命名为 `tmt1`
   - `tmt2.png` → 命名为 `tmt2`
   - `tmt3.png` → 命名为 `tmt3`

**图片位置**: `/Users/bojiang/Downloads/`
- tmt1.png
- tmt2.png
- tmt3.png

**详细步骤**:

```
1. 在Xcode中打开项目
2. 在左侧导航栏找到 "Assets.xcassets"（如果没有则创建）
3. 右键 Assets.xcassets → Add Files to "Assets.xcassets"
4. 选择三张番茄图片
5. 确保名称为：tmt1, tmt2, tmt3
6. 确认Target Membership勾选了StudyAI
```

---

## 🧪 测试清单

### 功能测试
- [ ] 完成专注后获得随机番茄
- [ ] 番茄正确显示在番茄园
- [ ] 统计数据正确更新
- [ ] 各类型番茄都能获得
- [ ] 筛选器正常工作
- [ ] 删除番茄功能正常
- [ ] 里程碑进度正确显示

### UI测试
- [ ] 番茄图片正确显示
- [ ] 完成动画流畅
- [ ] 番茄园布局合理
- [ ] 深色/浅色模式适配
- [ ] 不同屏幕尺寸适配

### 数据测试
- [ ] 数据持久化正常
- [ ] App重启后数据保留
- [ ] 大量番茄性能正常

---

## 💡 未来扩展建议

### 短期（1-2周）
- [ ] 添加更多番茄类型（4-6种）
- [ ] 番茄稀有度系统（普通/稀有/传说）
- [ ] 特殊成就徽章
- [ ] 分享番茄到社交媒体

### 中期（1个月）
- [ ] 番茄进化系统
- [ ] 番茄交易/赠送
- [ ] 番茄园装饰
- [ ] 每日任务/每周挑战

### 长期（2-3个月）
- [ ] 多用户番茄排行榜
- [ ] 番茄NFT收藏
- [ ] AR番茄展示
- [ ] Apple Watch番茄园

---

## 📊 代码统计

### 新增代码
- **TomatoType.swift**: ~150行
- **TomatoGardenService.swift**: ~200行
- **TomatoGardenView.swift**: ~400行
- **FocusView.swift修改**: ~50行

**总计**: ~800行新代码

### 删除代码
- 无（保留了旧的树木系统，可选择性删除）

---

## 🎯 设计理念

### 符合主题
- 番茄工作法 + 番茄奖励 = 完美契合
- 从"种树"改为"收集番茄"更贴切

### 收集乐趣
- 随机性增加惊喜感
- 多种类型增加收集欲望
- 统计和成就增加成就感

### 简洁美观
- 可爱的番茄形象
- 简洁的3列网格布局
- 直观的统计信息

### 激励机制
- 里程碑系统
- 成就系统
- 视觉反馈

---

## 🔗 相关文档

- `POMODORO_FEATURE_SUMMARY.md` - 番茄专注功能总览
- `FOCUS_UI_MODERNIZATION.md` - UI现代化改进
- `DEEP_FOCUS_UX_IMPROVEMENTS.md` - 深度专注优化

---

## 📝 重要提示

### ⚠️ 图片添加必需
项目需要添加三张番茄图片才能正常运行：
- tmt1.png
- tmt2.png
- tmt3.png

**当前位置**: `/Users/bojiang/Downloads/`

**请按照上面的步骤将图片添加到Xcode项目的Assets中。**

---

## 🎉 总结

番茄园功能已全面实现！主要特点：

✅ **三种可爱番茄** - 经典、卷藤、萌萌
✅ **随机获得机制** - 每次完成专注随机获得
✅ **完整的番茄园** - 展示、统计、筛选、删除
✅ **数据持久化** - UserDefaults保存
✅ **成就系统** - 里程碑和成就
✅ **现代化UI** - 简洁美观的界面

**下一步**: 在Xcode中添加三张番茄图片，然后构建运行项目！

---

**创建日期**: 2025年11月6日
**版本**: v1.0
**状态**: ✅ 代码完成，待添加图片
