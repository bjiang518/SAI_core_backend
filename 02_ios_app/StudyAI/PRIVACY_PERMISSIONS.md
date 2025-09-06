# Privacy Permissions Required

## Photo Library Access

The app now includes photo library access functionality. To enable this feature, you need to add the following privacy usage descriptions to your app's Info.plist or privacy configuration:

### Required Privacy Keys:

1. **NSPhotoLibraryUsageDescription**
   - Value: "StudyAI needs access to your photo library to let you upload homework images for AI analysis."

2. **NSCameraUsageDescription** (already likely present)
   - Value: "StudyAI needs camera access to scan homework documents."

### How to Add in Xcode:

1. Open your Xcode project
2. Navigate to the app target's Info tab
3. Add the following custom iOS target properties:
   - Key: `Privacy - Photo Library Usage Description`
   - Value: `StudyAI needs access to your photo library to let you upload homework images for AI analysis.`

### Implementation Notes:

- The `PhotoPermissionManager` class handles runtime permission requests
- Users will see a system permission dialog when first attempting to access photos
- If permission is denied, users are directed to Settings to enable access
- The `ImageSourceSelectionView` provides both camera and photo library options

### Features Added:

- **ImageSourceSelectionView**: New UI that lets users choose between camera or photo library
- **PhotoLibraryPicker**: UIImagePickerController wrapper for photo selection
- **PhotoPermissionManager**: Handles photo library permission requests
- **Enhanced Camera Options**: Users can now "Scan or Upload Homework" from AIHomeworkTestView

The implementation follows iOS best practices for privacy and provides clear user guidance when permissions are needed.