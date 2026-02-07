#!/bin/bash
# Database Bug Fixes Deployment Script
# Fixes for Production Database Errors (2026-01-30 through 2026-02-02)
#
# This script applies critical bug fixes to production database:
# 1. Fix ambiguous column reference in soft_delete_expired_data() function
# 2. Add missing ai_answer column to questions table

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}==================================="
echo "Database Bug Fixes Deployment"
echo -e "===================================${NC}\n"

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}ERROR: DATABASE_URL environment variable not set${NC}"
    echo "Please set DATABASE_URL to your PostgreSQL connection string"
    echo "Example: export DATABASE_URL='postgresql://user:pass@host:port/dbname'"
    exit 1
fi

echo -e "${GREEN}✓${NC} DATABASE_URL is set"

# Function to run SQL file
run_migration() {
    local file=$1
    local description=$2

    echo -e "\n${YELLOW}Running: $description${NC}"
    echo "File: $file"

    if psql "$DATABASE_URL" -f "$file" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Migration completed successfully"
        return 0
    else
        echo -e "${RED}✗${NC} Migration failed"
        return 1
    fi
}

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MIGRATIONS_DIR="$SCRIPT_DIR/../database/migrations"

# Track success/failure
FIXES_APPLIED=0
FIXES_FAILED=0

# Fix 1: Ambiguous column reference in soft_delete_expired_data()
echo -e "\n${YELLOW}[1/2] Fixing soft_delete_expired_data() function${NC}"
if run_migration "$MIGRATIONS_DIR/fix_data_retention_ambiguous_column.sql" "Fix ambiguous column reference"; then
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
else
    FIXES_FAILED=$((FIXES_FAILED + 1))
fi

# Fix 2: Add ai_answer column to questions table
echo -e "\n${YELLOW}[2/2] Adding ai_answer column to questions table${NC}"
if run_migration "$MIGRATIONS_DIR/add_ai_answer_column_to_questions.sql" "Add missing column"; then
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
else
    FIXES_FAILED=$((FIXES_FAILED + 1))
fi

# Summary
echo -e "\n${YELLOW}==================================="
echo "Deployment Summary"
echo -e "===================================${NC}"
echo -e "${GREEN}Fixes Applied:${NC} $FIXES_APPLIED"
echo -e "${RED}Fixes Failed:${NC} $FIXES_FAILED"

if [ $FIXES_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All fixes applied successfully!${NC}"
    echo -e "\nNext steps:"
    echo "1. Monitor logs for the next 24 hours"
    echo "2. Check that midnight cron job (soft_delete_expired_data) runs without errors"
    echo "3. Verify parent reports generation works correctly"
    exit 0
else
    echo -e "\n${RED}✗ Some fixes failed. Please review errors above.${NC}"
    exit 1
fi
