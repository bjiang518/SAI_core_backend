import Foundation

// 测试TomatoType.random()函数
// 运行1000次random()并统计每种番茄的生成次数

enum TomatoType: String, CaseIterable {
    case classic = "classic"    // 经典番茄 - tmt1
    case curly = "curly"        // 卷藤番茄 - tmt2
    case cute = "cute"          // 萌萌番茄 - tmt3
    case golden = "golden"      // 金色番茄 - tmt4
    case rainbow = "rainbow"    // 彩虹番茄 - tmt5
    case diamond = "diamond"    // 钻石番茄 - tmt6

    static func random() -> TomatoType {
        // 所有番茄类型拥有相同的概率（各16.67%）
        return TomatoType.allCases.randomElement() ?? .classic
    }
}

// 统计
var counts: [TomatoType: Int] = [:]
let iterations = 10000

print("测试 TomatoType.random() 生成 \(iterations) 次...")
print("期望概率：所有番茄类型均为 16.67% (1/6)\n")

for _ in 0..<iterations {
    let tomato = TomatoType.random()
    counts[tomato, default: 0] += 1
}

print("实际结果：")
for type in TomatoType.allCases {
    let count = counts[type] ?? 0
    let percentage = Double(count) / Double(iterations) * 100
    print("\(type.rawValue) (tmt\(TomatoType.allCases.firstIndex(of: type)! + 1)): \(count) 次 (\(String(format: "%.2f", percentage))%)")
}

print("\n总计: \(counts.values.reduce(0, +)) 次")
