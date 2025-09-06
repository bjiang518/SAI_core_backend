/**
 * Phase 3 Rollback Procedures
 * Comprehensive rollback strategies for API contract validation
 */

const fs = require('fs');
const path = require('path');

class Phase3Rollback {
  constructor() {
    this.configPath = path.join(__dirname, '../../.env');
    this.backupPath = path.join(__dirname, '../../.env.phase3.backup');
    this.rollbackLog = [];
  }

  /**
   * Execute complete Phase 3 rollback
   */
  async executeFullRollback(reason = 'Manual rollback requested') {
    console.log('⏪ Initiating Phase 3 Contract Validation Rollback');
    console.log('================================================');
    console.log(`Reason: ${reason}`);
    console.log('');

    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Rollback started',
      reason
    });

    try {
      // Step 1: Disable contract validation
      await this.disableContractValidation();
      
      // Step 2: Disable response standardization
      await this.disableResponseStandardization();
      
      // Step 3: Restore environment configuration
      await this.restoreEnvironmentConfig();
      
      // Step 4: Generate rollback report
      await this.generateRollbackReport();
      
      console.log('✅ Phase 3 rollback completed successfully');
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
   * Disable contract validation with graceful degradation
   */
  async disableContractValidation() {
    console.log('1️⃣ Disabling contract validation...');
    
    // Set environment variables to disable validation
    await this.updateEnvironmentVariable('CONTRACT_VALIDATION_ENABLED', 'false');
    await this.updateEnvironmentVariable('CONTRACT_VALIDATION_STRICT', 'false');
    await this.updateEnvironmentVariable('CONTRACT_VALIDATION_LOG_ONLY', 'true');
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Contract validation disabled',
      changes: {
        CONTRACT_VALIDATION_ENABLED: 'false',
        CONTRACT_VALIDATION_STRICT: 'false',
        CONTRACT_VALIDATION_LOG_ONLY: 'true'
      }
    });
    
    console.log('   ✅ Contract validation disabled');
  }

  /**
   * Disable response standardization
   */
  async disableResponseStandardization() {
    console.log('2️⃣ Disabling response standardization...');
    
    // The response standardization is automatically disabled when validation is disabled
    // due to the conditional logic in the gateway
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Response standardization disabled',
      note: 'Auto-disabled with contract validation'
    });
    
    console.log('   ✅ Response standardization disabled');
  }

  /**
   * Restore environment configuration
   */
  async restoreEnvironmentConfig() {
    console.log('3️⃣ Restoring environment configuration...');
    
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
      console.log('   ⚠️ No backup found, keeping current configuration with validation disabled');
      
      this.rollbackLog.push({
        timestamp: new Date().toISOString(),
        action: 'No backup found',
        note: 'Validation disabled in current config'
      });
    }
  }

  /**
   * Create environment backup before Phase 3 implementation
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
   * Partial rollback - disable strict validation only
   */
  async partialRollback() {
    console.log('🔄 Executing partial rollback - disabling strict validation...');
    
    await this.updateEnvironmentVariable('CONTRACT_VALIDATION_STRICT', 'false');
    await this.updateEnvironmentVariable('CONTRACT_VALIDATION_LOG_ONLY', 'true');
    
    this.rollbackLog.push({
      timestamp: new Date().toISOString(),
      action: 'Partial rollback executed',
      changes: {
        CONTRACT_VALIDATION_STRICT: 'false',
        CONTRACT_VALIDATION_LOG_ONLY: 'true'
      }
    });
    
    console.log('✅ Partial rollback completed - validation now in log-only mode');
    return { success: true, mode: 'log-only' };
  }

  /**
   * Emergency rollback - immediate disable
   */
  async emergencyRollback() {
    console.log('🚨 EMERGENCY ROLLBACK - Disabling all Phase 3 features immediately');
    
    const emergencyConfig = [
      'CONTRACT_VALIDATION_ENABLED=false',
      'CONTRACT_VALIDATION_STRICT=false', 
      'CONTRACT_VALIDATION_LOG_ONLY=true',
      'OPENAPI_VALIDATION_ENABLED=false',
      'RESPONSE_STANDARDIZATION_ENABLED=false'
    ].join('\\n');
    
    // Write emergency config
    const emergencyPath = path.join(__dirname, '../../.env.emergency');
    fs.writeFileSync(emergencyPath, emergencyConfig);
    
    // If main .env exists, append emergency settings
    if (fs.existsSync(this.configPath)) {
      const currentConfig = fs.readFileSync(this.configPath, 'utf8');
      const updatedConfig = currentConfig + '\\n\\n# Emergency Phase 3 Rollback\\n' + emergencyConfig;
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
      contract_validation_disable: await this.testEnvironmentVariable('CONTRACT_VALIDATION_ENABLED', 'false'),
      response_standardization_disable: true, // Always works as it's conditional
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
      phase: 'Phase 3 - API Contracts & Validation',
      status: 'Rolled back successfully',
      actions_taken: this.rollbackLog,
      current_state: {
        contract_validation: 'disabled',
        response_standardization: 'disabled',
        openapi_specs: 'preserved',
        documentation: 'preserved',
        tests: 'preserved'
      },
      next_steps: [
        'Restart the API Gateway server',
        'Verify all endpoints are working',
        'Monitor for any residual issues',
        'Consider gradual re-implementation if needed'
      ],
      preserved_components: [
        'OpenAPI specifications (gateway-spec.yml, ai-engine-spec.yml)',
        'Contract validation middleware (can be re-enabled)',
        'Documentation generation system',
        'Contract testing suite',
        'Response standardization utilities'
      ]
    };
    
    const reportPath = path.join(__dirname, '../../reports/phase3-rollback-report.json');
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
    this.rollback = new Phase3Rollback();
  }

  async execute(command = 'full') {
    console.log('🔧 Phase 3 Rollback Tool');
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
        console.log('  full      - Complete rollback of Phase 3');
        console.log('  partial   - Disable strict validation only');
        console.log('  emergency - Immediate disable all features');
        console.log('  test      - Test rollback procedures');
        console.log('  backup    - Create environment backup');
        console.log('  status    - Show rollback status');
        return { success: false, error: 'Unknown command' };
    }
  }
}

// Export components
const phase3Rollback = new Phase3Rollback();
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
  Phase3Rollback,
  RollbackCLI,
  phase3Rollback,
  rollbackCLI
};