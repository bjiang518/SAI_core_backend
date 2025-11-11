# 番茄图片添加指南

## 📸 需要添加的图片

以下三张番茄图片位于：`/Users/bojiang/Downloads/`

1. **tmt1.png** - 经典番茄
2. **tmt2.png** - 卷藤番茄
3. **tmt3.png** - 萌萌番茄

---

## 🔧 添加步骤

### 方法1：通过Xcode添加（推荐）

#### 步骤1：打开项目
```
1. 打开Xcode
2. 打开项目：StudyAI.xcodeproj
```

#### 步骤2：找到或创建Assets Catalog
```
1. 在左侧Project Navigator中查找
2. 寻找 "Assets.xcassets" 文件夹
3. 如果没有，创建一个：
   - 右键项目文件夹
   - New File
   - 选择 "Asset Catalog"
   - 命名为 "Assets"
```

#### 步骤3：添加图片
```
1. 点击选中 Assets.xcassets
2. 在Assets目录中，点击底部的 "+" 按钮
3. 选择 "Image Set"
4. 将新建的Image Set重命名为 "tmt1"
5. 拖拽 tmt1.png 到 Universal 槽位
6. 重复步骤2-5，添加 tmt2 和 tmt3
```

#### 步骤4：验证
```
1. 确保三个Image Set的名称为：
   - tmt1
   - tmt2
   - tmt3

2. 每个Image Set都有对应的png图片

3. 在右侧Inspector中确认：
   - Target Membership: StudyAI ✓
```

---

### 方法2：使用命令行（快速）

#### 复制图片
```bash
# 如果Assets.xcassets存在
cp /Users/bojiang/Downloads/tmt1.png /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI/Assets.xcassets/tmt1.imageset/tmt1.png

cp /Users/bojiang/Downloads/tmt2.png /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI/Assets.xcassets/tmt2.imageset/tmt2.png

cp /Users/bojiang/Downloads/tmt3.png /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI/Assets.xcassets/tmt3.imageset/tmt3.png
```

**注意**: 需要先在Xcode中创建对应的Image Set。

---

### 方法3：直接放在项目中（简单但不推荐）

#### 如果没有Assets Catalog
```bash
# 复制到项目根目录
cp /Users/bojiang/Downloads/tmt1.png /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI/

cp /Users/bojiang/Downloads/tmt2.png /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI/

cp /Users/bojiang/Downloads/tmt3.png /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI/
```

然后在Xcode中：
```
1. 右键StudyAI文件夹
2. Add Files to "StudyAI"
3. 选择三张图片
4. 确保勾选：
   - Copy items if needed ✓
   - Add to targets: StudyAI ✓
```

---

## 🧪 测试图片是否正确添加

### 在Xcode中测试

#### 方法1：Preview预览
```swift
struct TomatoPreview: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("tmt1")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)

            Image("tmt2")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)

            Image("tmt3")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
        }
    }
}
```

#### 方法2：构建并运行
```
1. 在Xcode中按 Cmd + B 构建
2. 检查是否有图片相关的警告或错误
3. 按 Cmd + R 运行
4. 完成一次专注
5. 查看获得的番茄是否正确显示
```

---

## ⚠️ 常见问题

### 问题1：图片不显示
**原因**:
- 图片名称不匹配
- 没有添加到Target

**解决**:
```
1. 检查Image Set名称是否为：tmt1, tmt2, tmt3
2. 在Xcode中选中图片
3. 右侧Inspector → Target Membership
4. 确保 StudyAI 被勾选
```

### 问题2：编译错误 "Cannot find 'tmt1' in scope"
**原因**:
- Xcode没有识别到图片

**解决**:
```
1. Clean Build Folder (Cmd + Shift + K)
2. 重新构建 (Cmd + B)
3. 如果还是不行，重启Xcode
```

### 问题3：图片显示模糊
**原因**:
- 图片分辨率不够

**解决**:
```
在Assets.xcassets中：
1. 选中Image Set
2. 在右侧Attributes Inspector中
3. 设置 Scale Factors: Single Scale
```

---

## 📐 图片规格建议

### 推荐尺寸
- **1x**: 150x150px
- **2x**: 300x300px（推荐）
- **3x**: 450x450px

### 文件格式
- PNG格式（带透明背景）
- RGB颜色空间

### 优化建议
```
使用工具压缩图片：
- ImageOptim (Mac)
- TinyPNG (在线)

目标文件大小：< 50KB per image
```

---

## 🔍 验证清单

构建前检查：

- [ ] 三张图片已添加到项目
- [ ] Image Set名称正确（tmt1, tmt2, tmt3）
- [ ] Target Membership已勾选StudyAI
- [ ] 图片格式为PNG
- [ ] 无编译警告

运行时检查：

- [ ] 完成专注后显示番茄图片
- [ ] 番茄园中显示番茄图片
- [ ] 三种番茄都能正常显示
- [ ] 图片清晰不模糊

---

## 💡 替代方案

如果暂时不想使用图片文件，可以使用Emoji作为临时方案：

### 修改TomatoType.swift

找到`imageName`属性，改为返回emoji：

```swift
var imageName: String {
    switch self {
    case .classic:
        return "🍅"  // emoji代替
    case .curly:
        return "🍅"
    case .cute:
        return "🍅"
    }
}
```

### 修改显示代码

在`TomatoGardenView.swift`和`FocusView.swift`中，将：

```swift
Image(tomato.type.imageName)
    .resizable()
    .scaledToFit()
```

改为：

```swift
Text(tomato.type.imageName)
    .font(.system(size: 80))
```

**注意**: 这只是临时方案，最好还是使用实际的PNG图片。

---

## 📚 相关资源

### 苹果官方文档
- [Adding Image Assets](https://developer.apple.com/documentation/xcode/adding-assets-to-your-app)
- [Asset Catalog Format](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/)

### 图片工具
- [ImageOptim](https://imageoptim.com/) - Mac图片压缩
- [TinyPNG](https://tinypng.com/) - 在线PNG压缩
- [Figma](https://figma.com/) - 编辑和导出图片

---

## 🎯 快速开始

最简单的方法：

```bash
# 1. 打开Xcode项目
open /Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI.xcodeproj

# 2. 在Finder中打开图片目录
open /Users/bojiang/Downloads/

# 3. 拖拽三张图片到Xcode的Assets.xcassets
# 4. 重命名为 tmt1, tmt2, tmt3
# 5. 构建运行 (Cmd + B, Cmd + R)
```

---

**创建日期**: 2025年11月6日
**用途**: 番茄园功能图片添加指南
