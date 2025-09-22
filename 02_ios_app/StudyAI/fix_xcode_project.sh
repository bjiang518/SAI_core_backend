#!/bin/bash

# Script to add the build files to the correct Sources build phase
PROJECT_DIR="/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI"
PROJECT_FILE="$PROJECT_DIR/StudyAI.xcodeproj/project.pbxproj"

echo "🔧 Adding files to Sources build phase..."

# The UUIDs from the previous run
QGS_BUILD_UUID="2E7243AADAB547CE8638CBD849FEBD0C"
QGDA_BUILD_UUID="503F4697500D43C48F59ED043FA46536"
QGV_BUILD_UUID="5D32BCFFDA004752B953D466A49492CA"
QDV_BUILD_UUID="F77F22EDC76D42A28F9549FB1E30C52E"
GQLV_BUILD_UUID="EB10D4604FA946ED950D43FDA91E84AE"

# Add to the Sources build phase (looking for the specific UUID pattern)
sed -i '' "/7B9EC4692E61663B005E4BFB \/\* Sources \*\/ = {/,/files = (/{
    /files = (/a\\
\\t\\t\\t\\t${QGS_BUILD_UUID} /* QuestionGenerationService.swift in Sources */,\\
\\t\\t\\t\\t${QGDA_BUILD_UUID} /* QuestionGenerationDataAdapter.swift in Sources */,\\
\\t\\t\\t\\t${QGV_BUILD_UUID} /* QuestionGenerationView.swift in Sources */,\\
\\t\\t\\t\\t${QDV_BUILD_UUID} /* QuestionDetailView.swift in Sources */,\\
\\t\\t\\t\\t${GQLV_BUILD_UUID} /* GeneratedQuestionsListView.swift in Sources */,
}" "$PROJECT_FILE"

echo "✅ Added files to Sources build phase"

# Now let's find and add to groups
echo "📂 Finding and adding to file groups..."

# Look for Services or similar group patterns
if grep -q "Services" "$PROJECT_FILE"; then
    echo "Found Services group references"
    # Add service files near other service files
    sed -i '' "/EnhancedTTSService.swift/a\\
\\t\\t\\t\\t2E7243AADAB547CE8638CBD849FEBD0C /* QuestionGenerationService.swift */,\\
\\t\\t\\t\\t503F4697500D43C48F59ED043FA46536 /* QuestionGenerationDataAdapter.swift */,
" "$PROJECT_FILE"
    echo "✅ Added service files to Services area"
fi

# Add view files near other view files
if grep -q "HomeView.swift" "$PROJECT_FILE"; then
    echo "Found Views area"
    sed -i '' "/HomeView.swift/a\\
\\t\\t\\t\\t5D32BCFFDA004752B953D466A49492CA /* QuestionGenerationView.swift */,\\
\\t\\t\\t\\tF77F22EDC76D42A28F9549FB1E30C52E /* QuestionDetailView.swift */,\\
\\t\\t\\t\\tEB10D4604FA946ED950D43FDA91E84AE /* GeneratedQuestionsListView.swift */,
" "$PROJECT_FILE"
    echo "✅ Added view files to Views area"
fi

echo ""
echo "🎉 Project file updated! Now testing build..."