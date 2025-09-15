#!/bin/bash

# Generate unique 24-character hex IDs
CAMERA_SESSION_REF_ID="CAS$(openssl rand -hex 10 | tr '[:lower:]' '[:upper:]')"
CAMERA_SESSION_BUILD_ID="CAB$(openssl rand -hex 10 | tr '[:lower:]' '[:upper:]')"

ENHANCED_IMAGE_REF_ID="EIR$(openssl rand -hex 10 | tr '[:lower:]' '[:upper:]')"
ENHANCED_IMAGE_BUILD_ID="EIB$(openssl rand -hex 10 | tr '[:lower:]' '[:upper:]')"

CAMERA_COMPAT_REF_ID="CCR$(openssl rand -hex 10 | tr '[:lower:]' '[:upper:]')"
CAMERA_COMPAT_BUILD_ID="CCB$(openssl rand -hex 10 | tr '[:lower:]' '[:upper:]')"

PROJECT_FILE="StudyAI.xcodeproj/project.pbxproj"

echo "Adding missing files to Xcode project..."
echo "CameraSessionManager.swift: $CAMERA_SESSION_REF_ID / $CAMERA_SESSION_BUILD_ID"
echo "EnhancedImageProcessor.swift: $ENHANCED_IMAGE_REF_ID / $ENHANCED_IMAGE_BUILD_ID"
echo "CameraCompatibilityManager.swift: $CAMERA_COMPAT_REF_ID / $CAMERA_COMPAT_BUILD_ID"

# Create backup
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

# Add build file entries
sed -i '' "/3CAC0FF7EDE94A0B9ACDC78F.*AuthenticationService\.swift.*Sources.*=.*{isa = PBXBuildFile;/a\\
		$CAMERA_SESSION_BUILD_ID /* StudyAI/Services/CameraSessionManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = $CAMERA_SESSION_REF_ID /* StudyAI/Services/CameraSessionManager.swift */; };\\
		$ENHANCED_IMAGE_BUILD_ID /* StudyAI/Services/EnhancedImageProcessor.swift in Sources */ = {isa = PBXBuildFile; fileRef = $ENHANCED_IMAGE_REF_ID /* StudyAI/Services/EnhancedImageProcessor.swift */; };\\
		$CAMERA_COMPAT_BUILD_ID /* StudyAI/Services/CameraCompatibilityManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = $CAMERA_COMPAT_REF_ID /* StudyAI/Services/CameraCompatibilityManager.swift */; };" "$PROJECT_FILE"

# Add file reference entries
sed -i '' "/DBB6C78FB23E45A9AF19ECC9.*StudyAI\/Services\/AuthenticationService\.swift.*=.*{isa = PBXFileReference;/a\\
		$CAMERA_SESSION_REF_ID /* StudyAI/Services/CameraSessionManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StudyAI/Services/CameraSessionManager.swift; sourceTree = \"<group>\"; };\\
		$ENHANCED_IMAGE_REF_ID /* StudyAI/Services/EnhancedImageProcessor.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StudyAI/Services/EnhancedImageProcessor.swift; sourceTree = \"<group>\"; };\\
		$CAMERA_COMPAT_REF_ID /* StudyAI/Services/CameraCompatibilityManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StudyAI/Services/CameraCompatibilityManager.swift; sourceTree = \"<group>\"; };" "$PROJECT_FILE"

# Add to files group
sed -i '' "/DBB6C78FB23E45A9AF19ECC9.*StudyAI\/Services\/AuthenticationService\.swift.*,/a\\
				$CAMERA_SESSION_REF_ID /* StudyAI/Services/CameraSessionManager.swift */,\\
				$ENHANCED_IMAGE_REF_ID /* StudyAI/Services/EnhancedImageProcessor.swift */,\\
				$CAMERA_COMPAT_REF_ID /* StudyAI/Services/CameraCompatibilityManager.swift */," "$PROJECT_FILE"

# Add to build sources
sed -i '' "/3CAC0FF7EDE94A0B9ACDC78F.*StudyAI\/Services\/AuthenticationService\.swift.*in Sources.*,/a\\
				$CAMERA_SESSION_BUILD_ID /* StudyAI/Services/CameraSessionManager.swift in Sources */,\\
				$ENHANCED_IMAGE_BUILD_ID /* StudyAI/Services/EnhancedImageProcessor.swift in Sources */,\\
				$CAMERA_COMPAT_BUILD_ID /* StudyAI/Services/CameraCompatibilityManager.swift in Sources */," "$PROJECT_FILE"

echo "✅ Files added to Xcode project successfully!"