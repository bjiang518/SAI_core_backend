# 🚀 Practice Generator Assistants API 部署指南

## 📋 部署前检查清单

### 1. 环境准备

```bash
cd /Users/bojiang/StudyAI_Workspace_GitHub/01_core_backend

# 检查依赖
npm list openai
# 应该显示: openai@4.20.1 或更高版本

# 检查环境变量
cat .env | grep OPENAI_API_KEY
# 应该有有效的 API key
```

### 2. 数据库迁移

```bash
# 连接到 Railway PostgreSQL 数据库
# 执行迁移脚本

psql $DATABASE_URL -f src/migrations/20251112_assistants_api_support.sql

# 验证表已创建
psql $DATABASE_URL -c "\dt assistants_config"
psql $DATABASE_URL -c "\dt openai_threads"
psql $DATABASE_URL -c "\dt assistant_metrics"
psql $DATABASE_URL -c "\dt daily_assistant_costs"
```

### 3. 创建 Practice Generator Assistant

```bash
# 运行初始化脚本
node scripts/initialize-assistants.js

# 输出应该包含:
# ✅ Practice Generator Assistant created: asst_xxxxxxxxxxxxx
# 📋 IMPORTANT: Update your .env file with the following:
# PRACTICE_GENERATOR_ASSISTANT_ID=asst_xxxxxxxxxxxxx
```

### 4. 更新环境变量

编辑 `.env` 文件，添加以下配置：

```bash
# 从初始化脚本复制 Assistant ID
PRACTICE_GENERATOR_ASSISTANT_ID=asst_xxxxxxxxxxxxx

# 功能开关（初始保持关闭）
USE_ASSISTANTS_API=false
ASSISTANTS_ROLLOUT_PERCENTAGE=0

# 其他配置使用默认值
AUTO_FALLBACK_ON_ERROR=true
AB_TEST_ENABLED=true
ASSISTANT_TIMEOUT_MS=60000
```

## 🧪 测试阶段

### Phase 1: 单元测试（本地）

```bash
# 设置测试环境
export USE_ASSISTANTS_API=false  # 先测试 fallback

# 运行测试
npm test

# 测试应该全部通过（使用 AI Engine fallback）
```

### Phase 2: Assistants API 功能测试

```javascript
// test-practice-generator.js
const { testPracticeGenerator } = require('./src/services/assistants/practice-generator-assistant');

async function runTest() {
  // 测试用户 ID（使用真实的用户 ID）
  const testUserId = 'your-test-user-id';

  try {
    console.log('🧪 Testing Practice Generator Assistant...\n');

    const result = await testPracticeGenerator(
      testUserId,
      'Mathematics',
      'Quadratic Equations'
    );

    console.log('✅ Test passed!');
    console.log('Generated questions:', JSON.stringify(result, null, 2));

    // 验证结果
    if (!result.questions || result.questions.length === 0) {
      throw new Error('No questions generated');
    }

    // 验证每个问题的结构
    result.questions.forEach((q, i) => {
      console.log(`\nQuestion ${i + 1}:`);
      console.log(`  ID: ${q.id}`);
      console.log(`  Type: ${q.question_type}`);
      console.log(`  Difficulty: ${q.difficulty}/5`);
      console.log(`  Question: ${q.question.substring(0, 100)}...`);

      // 验证必要字段
      if (!q.question || !q.correct_answer || !q.explanation) {
        throw new Error(`Question ${i + 1} missing required fields`);
      }
    });

    console.log('\n✅ All validations passed!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Test failed:', error);
    process.exit(1);
  }
}

runTest();
```

运行测试：

```bash
node test-practice-generator.js
```

### Phase 3: A/B 测试准备

```bash
# 启用 A/B 测试，但只给 5% 用户
cat >> .env << EOF
USE_ASSISTANTS_API=true
ASSISTANTS_ROLLOUT_PERCENTAGE=5
AB_TEST_ENABLED=true
EOF

# 重启服务
npm run dev
```

### Phase 4: 监控指标

```bash
# 查询 assistant_metrics 表
psql $DATABASE_URL << SQL
SELECT
  assistant_type,
  use_assistants_api,
  COUNT(*) as requests,
  AVG(total_latency_ms) as avg_latency,
  AVG(estimated_cost_usd) as avg_cost,
  SUM(CASE WHEN was_successful THEN 1 ELSE 0 END)::float / COUNT(*) as success_rate
FROM assistant_metrics
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY assistant_type, use_assistants_api;
SQL

# 查询每日成本
psql $DATABASE_URL << SQL
SELECT * FROM daily_assistant_costs ORDER BY date DESC LIMIT 7;
SQL
```

## 📊 渐进式发布计划

### Week 1: 5% 灰度

```bash
# .env 配置
ASSISTANTS_ROLLOUT_PERCENTAGE=5

# 监控指标
# - 错误率 < 1%
# - P95 延迟 < 5s
# - 成本 < AI Engine 成本 * 1.15
```

**成功标准**：
- ✅ 24 小时内无严重错误
- ✅ 用户反馈无投诉
- ✅ 成本在可控范围内

### Week 2: 25% 灰度

```bash
ASSISTANTS_ROLLOUT_PERCENTAGE=25

# 继续监控 7 天
```

**成功标准**：
- ✅ P95 延迟 < AI Engine P95 * 0.8
- ✅ 成功率 > 99%
- ✅ A/B 测试显示明显改善

### Week 3: 50% 灰度

```bash
ASSISTANTS_ROLLOUT_PERCENTAGE=50
```

**成功标准**：
- ✅ 所有指标持续稳定
- ✅ 成本节省明显（长对话场景）

### Week 4: 100% 全量

```bash
ASSISTANTS_ROLLOUT_PERCENTAGE=100

# 观察 3-7 天后，如果一切正常：
USE_ASSISTANTS_API=true
ASSISTANTS_ROLLOUT_PERCENTAGE=100
```

## 🔄 回滚计划

### 自动回滚触发条件

```bash
# 在 question-generation-v2.js 中已实现自动 fallback:
AUTO_FALLBACK_ON_ERROR=true
FALLBACK_ERROR_THRESHOLD=5  # 5 个连续错误后 fallback
```

### 手动紧急回滚

```bash
# 方法 1: 环境变量（最快）
export USE_ASSISTANTS_API=false
# 或者编辑 .env
echo "USE_ASSISTANTS_API=false" >> .env

# 重启服务（Railway 自动检测 .env 变化）
git commit -am "Emergency rollback: disable Assistants API"
git push origin main

# Railway 会在 2-3 分钟内重新部署
```

### 回滚验证

```bash
# 检查日志确认已回滚到 AI Engine
railway logs | grep "using_assistants_api"
# 应该显示: "using_assistants_api": false

# 检查指标
psql $DATABASE_URL << SQL
SELECT
  DATE_TRUNC('hour', created_at) as hour,
  use_assistants_api,
  COUNT(*) as requests
FROM assistant_metrics
WHERE created_at > NOW() - INTERVAL '6 hours'
GROUP BY hour, use_assistants_api
ORDER BY hour DESC;
SQL
```

## 📈 性能基准

### 预期指标（Assistants API）

| 指标 | 目标值 | AI Engine 基准 |
|------|--------|---------------|
| P50 延迟 | < 2.0s | 2.5s |
| P95 延迟 | < 3.5s | 4.5s |
| P99 延迟 | < 5.0s | 6.5s |
| 成功率 | > 99% | 98.5% |
| 成本/请求 | < $0.012 | $0.015 |

### 监控 Dashboard

创建 Grafana/DataDog dashboard 监控：

1. **请求量**
   - `assistants_api_requests` vs `ai_engine_requests`

2. **延迟分布**
   - P50, P95, P99 latency by implementation

3. **成本追踪**
   - Daily cost trend
   - Cost per request

4. **错误率**
   - Error count by error_code
   - Success rate trend

5. **A/B 测试对比**
   - Latency improvement %
   - Cost change %
   - Success rate delta

## 🛠️ 故障排查

### 问题 1: Assistant 返回无效 JSON

**症状**: `Invalid JSON response from assistant`

**解决方案**:
1. 检查 Assistant instructions 是否明确要求 JSON 格式
2. 查看 `response_format: { type: "json_object" }` 是否设置
3. 检查 OpenAI logs 查看原始响应

### 问题 2: Function calling 失败

**症状**: `Run failed: function execution error`

**解决方案**:
1. 检查数据库连接
2. 验证 `get_student_performance` 和 `get_common_mistakes` 返回正确格式
3. 查看 function_call_cache 表是否正常

### 问题 3: 成本超预算

**症状**: Daily cost > $50

**解决方案**:
1. 检查是否有用户滥用
2. 降低 `ASSISTANTS_ROLLOUT_PERCENTAGE`
3. 添加更严格的 rate limiting

## ✅ 最终检查清单

部署前确认：

- [ ] 数据库迁移已执行
- [ ] Assistant 已创建并 ID 已配置
- [ ] 环境变量已正确设置
- [ ] 单元测试全部通过
- [ ] 功能测试成功
- [ ] Fallback 逻辑已验证
- [ ] 监控 dashboard 已配置
- [ ] 告警规则已设置
- [ ] 回滚计划已准备
- [ ] 团队成员已培训

部署后 24 小时监控：

- [ ] 检查错误率 < 1%
- [ ] 验证 A/B 测试数据收集正常
- [ ] 确认成本在预算内
- [ ] 用户反馈无异常
- [ ] 性能指标达标

**祝部署顺利！** 🎉
