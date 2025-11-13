#!/usr/bin/env node

/**
 * 一键设置和测试 Assistants API
 *
 * 这个脚本会：
 * 1. ✅ 检查环境变量
 * 2. 📊 执行数据库迁移
 * 3. 🤖 创建 Practice Generator Assistant
 * 4. ⚙️  更新 .env 配置
 * 5. 🧪 运行测试验证
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { db } = require('../src/utils/railway-database');
const { createPracticeGeneratorAssistant, testPracticeGenerator } = require('../src/services/assistants/practice-generator-assistant');

async function main() {
  console.log('🚀 StudyAI Assistants API - 快速设置和测试\n');
  console.log('='.repeat(60));

  try {
    // Step 1: 检查环境变量
    console.log('\n📋 Step 1: 检查环境变量...');
    if (!process.env.OPENAI_API_KEY) {
      throw new Error('❌ OPENAI_API_KEY 未设置！请在 .env 文件中配置');
    }
    console.log('✅ OPENAI_API_KEY: ' + process.env.OPENAI_API_KEY.substring(0, 20) + '...');

    if (!process.env.DATABASE_URL) {
      throw new Error('❌ DATABASE_URL 未设置！');
    }
    console.log('✅ DATABASE_URL: 已配置');

    // Step 2: 数据库连接测试
    console.log('\n📊 Step 2: 测试数据库连接...');
    const testResult = await db.query('SELECT NOW() as current_time');
    console.log('✅ 数据库连接成功:', testResult.rows[0].current_time);

    // Step 3: 执行数据库迁移
    console.log('\n📊 Step 3: 执行数据库迁移...');
    const migrationPath = path.join(__dirname, '../src/migrations/20251112_assistants_api_support_v2.sql');

    if (!fs.existsSync(migrationPath)) {
      throw new Error('❌ 迁移文件不存在: ' + migrationPath);
    }

    const migrationSQL = fs.readFileSync(migrationPath, 'utf8');

    try {
      await db.query(migrationSQL);
      console.log('✅ 数据库迁移成功');
    } catch (error) {
      if (error.message.includes('already exists')) {
        console.log('ℹ️  迁移已执行过（表已存在）');
      } else {
        throw error;
      }
    }

    // 验证表已创建
    const tables = ['assistants_config', 'openai_threads', 'assistant_metrics', 'daily_assistant_costs', 'function_call_cache'];
    for (const table of tables) {
      const result = await db.query(`SELECT COUNT(*) FROM ${table}`);
      console.log(`  ✅ ${table}: ${result.rows[0].count} 行`);
    }

    // Step 4: 检查是否已有 Assistant
    console.log('\n🤖 Step 4: 检查/创建 Practice Generator Assistant...');
    const existingAssistant = await db.query(`
      SELECT openai_assistant_id
      FROM assistants_config
      WHERE purpose = 'practice_generator'
        AND openai_assistant_id NOT LIKE 'asst_placeholder%'
      LIMIT 1
    `);

    let assistantId;

    if (existingAssistant.rows.length > 0) {
      assistantId = existingAssistant.rows[0].openai_assistant_id;
      console.log('ℹ️  Assistant 已存在:', assistantId);
      console.log('   如需重新创建，请先删除数据库记录');
    } else {
      console.log('📝 创建新的 Practice Generator Assistant...');
      const result = await createPracticeGeneratorAssistant();
      assistantId = result.assistant_id;
      console.log('✅ Assistant 创建成功:', assistantId);
    }

    // Step 5: 更新 .env 文件
    console.log('\n⚙️  Step 5: 更新 .env 配置...');
    const envPath = path.join(__dirname, '../.env');
    let envContent = fs.readFileSync(envPath, 'utf8');

    // 检查是否已有配置
    const configsToAdd = {
      'PRACTICE_GENERATOR_ASSISTANT_ID': assistantId,
      'USE_ASSISTANTS_API': 'false',  // 先保持关闭，测试后再开启
      'ASSISTANTS_ROLLOUT_PERCENTAGE': '0',
      'AUTO_FALLBACK_ON_ERROR': 'true',
      'AB_TEST_ENABLED': 'true',
      'ASSISTANT_TIMEOUT_MS': '60000',
      'ASSISTANT_POLLING_INTERVAL_MS': '500',
      'ASSISTANT_MAX_RETRIES': '2'
    };

    let envUpdated = false;
    for (const [key, value] of Object.entries(configsToAdd)) {
      if (!envContent.includes(key + '=')) {
        envContent += `\n${key}=${value}`;
        envUpdated = true;
        console.log(`  ✅ 添加: ${key}=${value}`);
      } else {
        console.log(`  ℹ️  已存在: ${key}`);
      }
    }

    if (envUpdated) {
      fs.writeFileSync(envPath, envContent);
      console.log('✅ .env 文件已更新');
      console.log('⚠️  请重新加载环境变量: source .env 或重启服务');
    } else {
      console.log('ℹ️  .env 配置已是最新');
    }

    // Step 6: 运行测试（如果有测试用户）
    console.log('\n🧪 Step 6: 运行测试...');
    console.log('ℹ️  正在查找测试用户...');

    const testUserResult = await db.query(`
      SELECT id FROM users LIMIT 1
    `);

    if (testUserResult.rows.length === 0) {
      console.log('⚠️  数据库中没有用户，跳过功能测试');
      console.log('   提示: 创建用户后运行 npm run test:assistant 进行测试');
    } else {
      const testUserId = testUserResult.rows[0].id;
      console.log(`✅ 使用测试用户: ${testUserId}`);

      console.log('\n开始生成测试题目...');
      const testResult = await testPracticeGenerator(
        testUserId,
        'Mathematics',
        'Quadratic Equations'
      );

      // Check if result contains error or questions
      if (testResult.error) {
        console.log('\n⚠️  Assistant 返回错误响应:');
        console.log('  Error:', testResult.error);
        console.log('  Message:', testResult.message);
        if (testResult.suggestions) {
          console.log('  Suggestions:', testResult.suggestions);
        }
      } else if (testResult.questions && testResult.questions.length > 0) {
        console.log('\n✅ 测试成功！生成了', testResult.questions.length, '个问题');
        console.log('\n示例问题:');
        if (testResult.questions[0]) {
          console.log('  Question:', testResult.questions[0].question.substring(0, 100) + '...');
          console.log('  Type:', testResult.questions[0].question_type);
          console.log('  Difficulty:', testResult.questions[0].difficulty + '/5');
        }
      } else {
        console.log('\n⚠️  未知响应格式:', JSON.stringify(testResult, null, 2));
      }
    }

    // Step 7: 总结
    console.log('\n' + '='.repeat(60));
    console.log('🎉 设置完成！\n');
    console.log('📋 下一步操作:');
    console.log('1. 运行完整测试: npm test');
    console.log('2. 启动开发服务器: npm run dev');
    console.log('3. 测试新接口: POST /api/ai/generate-questions/practice');
    console.log('4. 查看监控数据:');
    console.log('   psql $DATABASE_URL -c "SELECT * FROM assistant_metrics LIMIT 5"');
    console.log('\n📖 详细文档: DEPLOYMENT_GUIDE_ASSISTANTS_API.md');
    console.log('\n🔧 当前配置:');
    console.log('   - USE_ASSISTANTS_API: false (测试后改为 true)');
    console.log('   - ASSISTANTS_ROLLOUT_PERCENTAGE: 0% (逐步提升到 5% → 100%)');
    console.log('   - AUTO_FALLBACK_ON_ERROR: true');
    console.log('\n✅ 准备就绪！');

    process.exit(0);
  } catch (error) {
    console.error('\n❌ 设置失败:', error.message);
    console.error('\n详细错误:', error);
    console.error('\n🔧 故障排查:');
    console.error('1. 检查 OPENAI_API_KEY 是否有效');
    console.error('2. 检查 DATABASE_URL 是否正确');
    console.error('3. 确保数据库可访问');
    console.error('4. 查看上方详细错误信息');
    process.exit(1);
  }
}

// 运行主函数
if (require.main === module) {
  main();
}

module.exports = { main };
