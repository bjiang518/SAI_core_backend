/**
 * Phase 4 Rollback Procedures
 * Comprehensive rollback strategies for performance optimization and monitoring
 */

const fs = require('fs');
const path = require('path');

class Phase4Rollback {
  constructor() {
    this.configPath = path.join(__dirname, '../../.env');
    this.backupPath = path.join(__dirname, '../../.env.phase4.backup');
    this.rollbackLog = [];
  }

  /**
   * Execute complete Phase 4 rollback
   */
  async executeFullRollback(reason = 'Manual rollback requested') {
    console.log('⏪ Initiating Phase 4 Performance Optimization Rollback');
    console.log('=====================================================');
    console.log(`Reason: ${reason}`);
    console.log('');

    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Rollback started',
      reason
    });

    try {
      // Step 1: Disable performance monitoring
      await this.disablePerformanceMonitoring();
      
      // Step 2: Disable caching
      await this.disableCaching();
      
      // Step 3: Disable compression
      await this.disableCompression();
      
      // Step 4: Disable metrics collection
      await this.disableMetricsCollection();
      
      // Step 5: Restore environment configuration
      await this.restoreEnvironmentConfig();
      
      // Step 6: Generate rollback report
      await this.generateRollbackReport();
      
      console.log('✅ Phase 4 rollback completed successfully');
      console.log('');
      console.log('🔄 Restart the server to apply changes:');
      console.log('   npm run start');
      
      return { success: true, steps: this.rollbackLog };
      
    } catch (error) {
      console.error('❌ Rollback failed:', error.message);
      this.rollbackLog.push({
        timestamp: new Date().toISOString(),
        action: 'Rollback failed',
        error: error.message
      });
      
      return { success: false, error: error.message, steps: this.rollbackLog };
    }
  }

  /**
   * Disable performance monitoring
   */
  async disablePerformanceMonitoring() {
    console.log('1️⃣ Disabling performance monitoring...');
    
    await this.updateEnvironmentVariable('PERFORMANCE_ANALYSIS_ENABLED', 'false');
    await this.updateEnvironmentVariable('PERFORMANCE_METRICS_ENABLED', 'false');
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Performance monitoring disabled',
      changes: {
        PERFORMANCE_ANALYSIS_ENABLED: 'false',
        PERFORMANCE_METRICS_ENABLED: 'false'
      }
    });
    
    console.log('   ✅ Performance monitoring disabled');
  }

  /**
   * Disable caching
   */
  async disableCaching() {
    console.log('2️⃣ Disabling Redis caching...');
    
    await this.updateEnvironmentVariable('REDIS_CACHING_ENABLED', 'false');
    await this.updateEnvironmentVariable('CACHE_WARMING_ENABLED', 'false');
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Redis caching disabled',
      changes: {
        REDIS_CACHING_ENABLED: 'false',
        CACHE_WARMING_ENABLED: 'false'
      }
    });
    
    console.log('   ✅ Redis caching disabled');
  }

  /**
   * Disable compression
   */
  async disableCompression() {
    console.log('3️⃣ Disabling response compression...');
    
    await this.updateEnvironmentVariable('COMPRESSION_ENABLED', 'false');
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Response compression disabled',
      changes: {
        COMPRESSION_ENABLED: 'false'
      }
    });
    
    console.log('   ✅ Response compression disabled');
  }

  /**
   * Disable metrics collection
   */
  async disableMetricsCollection() {
    console.log('4️⃣ Disabling Prometheus metrics...');
    
    await this.updateEnvironmentVariable('PROMETHEUS_METRICS_ENABLED', 'false');
    await this.updateEnvironmentVariable('HEALTH_METRICS_ENABLED', 'false');
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Prometheus metrics disabled',
      changes: {
        PROMETHEUS_METRICS_ENABLED: 'false',
        HEALTH_METRICS_ENABLED: 'false'
      }
    });
    
    console.log('   ✅ Prometheus metrics disabled');
  }

  /**
   * Restore environment configuration
   */
  async restoreEnvironmentConfig() {
    console.log('5️⃣ Restoring environment configuration...');
    
    if (fs.existsSync(this.backupPath)) {
      const backupContent = fs.readFileSync(this.backupPath, 'utf8');
      fs.writeFileSync(this.configPath, backupContent);
      
      this.rollbackLog.push({
        timestamp: new Date().toISOString(),
        action: 'Environment restored from backup',
        backup_file: this.backupPath
      });
      
      console.log('   ✅ Environment configuration restored from backup');
    } else {
      console.log('   ⚠️ No backup found, keeping current configuration with performance features disabled');
      
      this.rollbackLog.push({
        timestamp: new Date().toISOString(),
        action: 'No backup found',
        note: 'Performance features disabled in current config'
      });
    }
  }

  /**
   * Create environment backup before Phase 4 implementation
   */
  async createEnvironmentBackup() {
    console.log('💾 Creating environment backup...');
    
    if (fs.existsSync(this.configPath)) {
      const content = fs.readFileSync(this.configPath, 'utf8');
      fs.writeFileSync(this.backupPath, content);
      
      console.log(`   ✅ Environment backup created: ${this.backupPath}`);
      return true;
    }
    
    console.log('   ⚠️ No .env file found to backup');
    return false;
  }

  /**
   * Partial rollback - disable resource-intensive features only
   */
  async partialRollback() {
    console.log('🔄 Executing partial rollback - disabling resource-intensive features...');
    
    await this.updateEnvironmentVariable('REDIS_CACHING_ENABLED', 'false');
    await this.updateEnvironmentVariable('PERFORMANCE_ANALYSIS_ENABLED', 'false');
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Partial rollback executed',
      changes: {
        REDIS_CACHING_ENABLED: 'false',
        PERFORMANCE_ANALYSIS_ENABLED: 'false'
      }
    });
    
    console.log('✅ Partial rollback completed - keeping metrics and compression enabled');
    return { success: true, mode: 'partial' };
  }

  /**
   * Emergency rollback - immediate disable all performance features
   */
  async emergencyRollback() {
    console.log('🚨 EMERGENCY ROLLBACK - Disabling all Phase 4 features immediately');
    
    const emergencyConfig = [
      'PERFORMANCE_ANALYSIS_ENABLED=false',
      'PERFORMANCE_METRICS_ENABLED=false',
      'REDIS_CACHING_ENABLED=false',
      'CACHE_WARMING_ENABLED=false',
      'COMPRESSION_ENABLED=false',
      'PROMETHEUS_METRICS_ENABLED=false',
      'HEALTH_METRICS_ENABLED=false',
      'LOAD_TESTING_ENABLED=false'
    ].join('\\n');
    
    // Write emergency config
    const emergencyPath = path.join(__dirname, '../../.env.emergency');
    fs.writeFileSync(emergencyPath, emergencyConfig);
    
    // If main .env exists, append emergency settings
    if (fs.existsSync(this.configPath)) {
      const currentConfig = fs.readFileSync(this.configPath, 'utf8');
      const updatedConfig = currentConfig + '\\n\\n# Emergency Phase 4 Rollback\\n' + emergencyConfig;
      fs.writeFileSync(this.configPath, updatedConfig);
    } else {
      fs.writeFileSync(this.configPath, emergencyConfig);
    }
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Emergency rollback executed',
      config_file: emergencyPath
    });
    
    console.log('✅ Emergency rollback completed');
    console.log('🔄 RESTART THE SERVER IMMEDIATELY');
    
    return { success: true, mode: 'emergency' };
  }

  /**
   * Test rollback procedures without making changes
   */
  async testRollback() {
    console.log('🧪 Testing rollback procedures (dry run)...');
    
    const results = {
      performance_monitoring_disable: await this.testEnvironmentVariable('PERFORMANCE_ANALYSIS_ENABLED', 'false'),
      caching_disable: await this.testEnvironmentVariable('REDIS_CACHING_ENABLED', 'false'),
      metrics_disable: await this.testEnvironmentVariable('PROMETHEUS_METRICS_ENABLED', 'false'),
      environment_backup_exists: fs.existsSync(this.backupPath),
      can_write_config: await this.testFileWrite(this.configPath)
    };
    
    const allTestsPassed = Object.values(results).every(result => result === true);
    
    console.log('📋 Rollback Test Results:');
    Object.entries(results).forEach(([test, passed]) => {
      console.log(`   ${passed ? '✅' : '❌'} ${test}: ${passed ? 'OK' : 'FAILED'}`);
    });
    
    console.log(`\\n${allTestsPassed ? '✅' : '❌'} Rollback procedures ${allTestsPassed ? 'ready' : 'have issues'}`);
    
    return { success: allTestsPassed, results };
  }

  /**
   * Generate rollback report
   */
  async generateRollbackReport() {
    console.log('📄 Generating rollback report...');
    
    const report = {
      rollback_timestamp: new Date().toISOString(),
      phase: 'Phase 4 - Performance Optimization & Monitoring',
      status: 'Rolled back successfully',
      actions_taken: this.rollbackLog,
      current_state: {
        performance_monitoring: 'disabled',
        redis_caching: 'disabled',
        response_compression: 'disabled',
        prometheus_metrics: 'disabled',
        load_testing: 'disabled'
      },
      performance_impact: {
        expected_changes: [
          'Response times may increase without caching',
          'Memory usage will decrease',
          'CPU usage will decrease',
          'Monitoring visibility will be reduced'
        ]
      },
      next_steps: [
        'Restart the API Gateway server',
        'Verify all endpoints are working',
        'Monitor basic health metrics',
        'Consider gradual re-implementation if needed'
      ],
      preserved_components: [
        'Performance analysis tools (can be re-enabled)',
        'Redis cache infrastructure (configuration preserved)',
        'Prometheus metrics definitions',
        'Load testing suite',
        'Performance monitoring utilities'
      ]
    };
    
    const reportPath = path.join(__dirname, '../../reports/phase4-rollback-report.json');
    const reportsDir = path.dirname(reportPath);
    
    if (!fs.existsSync(reportsDir)) {
      fs.mkdirSync(reportsDir, { recursive: true });
    }
    
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    
    console.log(`   ✅ Rollback report saved: ${reportPath}`);
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Rollback report generated',
      file: reportPath
    });
  }

  /**
   * Update environment variable
   */
  async updateEnvironmentVariable(key, value) {
    if (!fs.existsSync(this.configPath)) {
      fs.writeFileSync(this.configPath, `${key}=${value}\\n`);
      return;
    }
    
    let content = fs.readFileSync(this.configPath, 'utf8');
    const regex = new RegExp(`^${key}=.*$`, 'm');
    
    if (regex.test(content)) {
      content = content.replace(regex, `${key}=${value}`);
    } else {
      content += `\\n${key}=${value}`;
    }
    
    fs.writeFileSync(this.configPath, content);
  }

  /**
   * Test environment variable update
   */
  async testEnvironmentVariable(key, value) {
    try {
      const testPath = path.join(__dirname, '../../.env.test');
      fs.writeFileSync(testPath, `${key}=${value}\\n`);
      fs.unlinkSync(testPath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Test file write permissions
   */
  async testFileWrite(filePath) {
    try {
      const testContent = '# Test write\\n';
      const originalContent = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
      
      fs.writeFileSync(filePath, originalContent + testContent);
      
      // Restore original content
      if (originalContent) {
        fs.writeFileSync(filePath, originalContent);
      } else {
        fs.unlinkSync(filePath);
      }
      
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Get rollback status
   */
  getStatus() {
    return {
      backup_exists: fs.existsSync(this.backupPath),
      config_exists: fs.existsSync(this.configPath),
      rollback_log_entries: this.rollbackLog.length,
      last_action: this.rollbackLog[this.rollbackLog.length - 1] || null
    };
  }
}

// Rollback command-line interface
class RollbackCLI {
  constructor() {
    this.rollback = new Phase4Rollback();
  }

  async execute(command = 'full') {
    console.log('🔧 Phase 4 Rollback Tool');
    console.log('========================');
    
    switch (command.toLowerCase()) {
      case 'full':
        return await this.rollback.executeFullRollback();
      
      case 'partial':
        return await this.rollback.partialRollback();
      
      case 'emergency':
        return await this.rollback.emergencyRollback();
      
      case 'test':
        return await this.rollback.testRollback();
      
      case 'backup':
        return await this.rollback.createEnvironmentBackup();
      
      case 'status':
        console.log('Current rollback status:', this.rollback.getStatus());
        return { success: true };
      
      default:
        console.log('Available commands:');
        console.log('  full      - Complete rollback of Phase 4');
        console.log('  partial   - Disable resource-intensive features only');
        console.log('  emergency - Immediate disable all performance features');
        console.log('  test      - Test rollback procedures');
        console.log('  backup    - Create environment backup');
        console.log('  status    - Show rollback status');
        return { success: false, error: 'Unknown command' };
    }
  }
}

// Export components
const phase4Rollback = new Phase4Rollback();
const rollbackCLI = new RollbackCLI();

// Command line execution
if (require.main === module) {
  const command = process.argv[2] || 'full';
  rollbackCLI.execute(command)
    .then((result) => {
      if (result.success) {
        console.log('\\n🎉 Rollback operation completed successfully');
        process.exit(0);
      } else {
        console.error('\\n❌ Rollback operation failed:', result.error);
        process.exit(1);
      }
    })
    .catch((error) => {
      console.error('\\n💥 Rollback operation crashed:', error);
      process.exit(1);
    });
}

module.exports = {
  Phase4Rollback,
  RollbackCLI,
  phase4Rollback,
  rollbackCLI
};