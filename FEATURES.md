# Watchdawg Feature Roadmap

Features ranked by implementation complexity (easiest first).

---

## Phase 1: Quick Wins (1-2 days each)

### 1. Local Push Notifications
**Complexity:** ⭐ Easy
**Value:** High

Alert users when recording starts/stops or when motion is detected.

**Implementation:**
- Use `UserNotifications` framework (built into macOS 10.14+)
- Request notification permission on first launch
- Trigger `UNNotificationRequest` on events

```swift
import UserNotifications

UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in }

let content = UNMutableNotificationContent()
content.title = "Motion Detected"
content.sound = .default

let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
UNUserNotificationCenter.current().add(request)
```

**References:**
- [Apple UserNotifications Documentation](https://developer.apple.com/documentation/usernotifications)

---

### 2. Scheduled Recording
**Complexity:** ⭐ Easy
**Value:** Medium

Set time windows for automatic recording (e.g., 10pm-6am).

**Implementation:**
- Add `startTime` and `endTime` to settings (stored in `UserDefaults`)
- Use `Timer` or `DispatchQueue.asyncAfter` to check schedule
- Auto-arm/disarm based on current time

```swift
struct Schedule: Codable {
    var enabled: Bool
    var startHour: Int  // 0-23
    var endHour: Int
}

func shouldBeRecording() -> Bool {
    let hour = Calendar.current.component(.hour, from: Date())
    return hour >= schedule.startHour || hour < schedule.endHour
}
```

---

### 3. Recording Export/Share
**Complexity:** ⭐ Easy
**Value:** Medium

Export recordings to Files, AirDrop, or other apps.

**Implementation:**
- Use `NSSharingServicePicker` for macOS share sheet
- Add "Export" button to recording detail view

```swift
let picker = NSSharingServicePicker(items: [recording.url])
picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
```

---

## Phase 2: Core Features (3-5 days each)

### 4. Sentry Mode (Motion Detection)
**Complexity:** ⭐⭐ Medium
**Value:** Very High

Only record when motion is detected. Saves storage and makes review easier.

**Implementation:**
Two approaches (recommend starting with A):

#### A. Frame Differencing (Simple, CPU-efficient)
Compare consecutive frames, detect pixel changes above threshold.

```swift
import CoreImage
import Accelerate

class MotionDetector {
    private var previousFrame: CVPixelBuffer?
    private let threshold: Float = 0.02  // 2% of pixels changed

    func detectMotion(in frame: CVPixelBuffer) -> Bool {
        defer { previousFrame = frame }
        guard let previous = previousFrame else { return false }

        // Convert to grayscale, compute absolute difference
        let diff = absDifference(previous, frame)
        let changedPixels = countAboveThreshold(diff, threshold: 25)
        let totalPixels = CVPixelBufferGetWidth(frame) * CVPixelBufferGetHeight(frame)

        return Float(changedPixels) / Float(totalPixels) > threshold
    }
}
```

**Algorithm:**
1. Convert frame to grayscale
2. Compute `abs(currentFrame - previousFrame)`
3. Apply threshold to remove noise (pixel diff > 25)
4. If >2% of pixels changed → motion detected
5. Use 3-frame differencing to reduce false positives

#### B. Background Subtraction (More robust)
Use running average of background, detect foreground objects.

**References:**
- [Frame Differencing Tutorial](https://medium.com/@itberrios6/introduction-to-motion-detection-part-1-e031b0bb9bb2)
- [OpenCV Motion Detection](https://learnopencv.com/moving-object-detection-with-opencv/)

**Integration points:**
- Add `MotionDetector` class
- In `CameraManager`, check motion before starting chunk
- Add sensitivity slider in Settings (adjust threshold)
- Add toggle: "Sentry Mode" on Home tab

---

### 5. Activity Zones
**Complexity:** ⭐⭐ Medium
**Value:** High

Define regions of the frame to monitor. Ignore motion outside zones.

**Implementation:**
- Let user draw rectangles on preview
- Store as normalized coordinates (0-1 range)
- In motion detection, only check pixels within zones

```swift
struct ActivityZone: Codable {
    var rect: CGRect  // normalized 0-1
    var name: String
}

func isInZone(_ point: CGPoint, zones: [ActivityZone]) -> Bool {
    zones.contains { $0.rect.contains(point) }
}
```

**UI:**
- Overlay on camera preview
- Drag to create zones
- Tap to delete

---

### 6. Configurable Retention Period
**Complexity:** ⭐ Easy
**Value:** Medium

Let users choose how long to keep recordings (1h, 12h, 24h, 48h, 7d, forever).

**Implementation:**
- Add picker in Settings
- Update `TTLCleaner.ttl` based on selection
- Store in `UserDefaults`

---

## Phase 3: AI Features (1-2 weeks each)

### 7. Person Detection
**Complexity:** ⭐⭐⭐ Hard
**Value:** Very High

Detect humans vs. pets vs. cars. Reduce false alarms from shadows/trees.

**Implementation:**
Use Apple's Vision framework with CoreML model.

**Option A: Built-in Vision (Easiest)**
```swift
import Vision

let request = VNDetectHumanRectanglesRequest { request, error in
    guard let results = request.results as? [VNHumanObservation] else { return }
    if !results.isEmpty {
        // Person detected
    }
}

let handler = VNImageRequestHandler(cvPixelBuffer: frame)
try? handler.perform([request])
```

**Option B: YOLOv8 CoreML (More accurate, detects multiple classes)**
1. Export YOLOv8n to CoreML: `model.export(format="coreml")`
2. Add .mlpackage to Xcode project
3. Run inference on frames

```swift
let model = try! YOLOv8n(configuration: MLModelConfiguration())
let request = VNCoreMLRequest(model: try! VNCoreMLModel(for: model.model)) { request, _ in
    guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
    let people = results.filter { $0.labels.first?.identifier == "person" }
}
```

**References:**
- [Ultralytics CoreML Export](https://docs.ultralytics.com/integrations/coreml/)
- [ObjectDetection-CoreML](https://github.com/tucan9389/ObjectDetection-CoreML)
- [Apple Vision Framework](https://developer.apple.com/documentation/vision)

---

### 8. Face Recognition (Familiar Faces)
**Complexity:** ⭐⭐⭐ Hard
**Value:** High

Recognize known faces to reduce alerts for family members.

**Implementation:**
1. Use `VNDetectFaceRectanglesRequest` to find faces
2. Use `VNFaceObservation` to get face embeddings
3. Store embeddings for "known" faces
4. Compare new faces using cosine similarity

```swift
let faceRequest = VNDetectFaceLandmarksRequest()
// Extract face region, generate embedding, compare to stored faces
```

**Privacy note:** All processing is local, no cloud upload.

---

## Phase 4: Cloud Storage (1-2 weeks)

### 9. Google Drive Integration
**Complexity:** ⭐⭐⭐ Hard
**Value:** High

Auto-upload recordings to Google Drive.

**Implementation:**
1. Add [swift-google-drive-client](https://github.com/darrarski/swift-google-drive-client) via SPM
2. Register app in Google Cloud Console
3. Implement OAuth flow (redirect to browser on macOS)
4. Upload completed recordings in background

```swift
import GoogleDriveClient

let client = GoogleDriveClient(
    clientID: "your-client-id",
    authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
    // ...
)

// Upload file
try await client.uploadFile(
    name: recording.filename,
    data: Data(contentsOf: recording.url),
    mimeType: "video/mp4"
)
```

**References:**
- [swift-google-drive-client](https://github.com/darrarski/swift-google-drive-client)
- [Google Drive API](https://developers.google.com/workspace/drive/api/guides/about-sdk)

---

### 10. Dropbox Integration
**Complexity:** ⭐⭐⭐ Hard
**Value:** High

Auto-upload recordings to Dropbox.

**Implementation:**
1. Add [SwiftyDropbox](https://github.com/dropbox/SwiftyDropbox) via SPM
2. Register app in Dropbox App Console
3. Implement OAuth (opens browser)
4. Upload completed recordings

```swift
import SwiftyDropbox

DropboxClientsManager.authorizeFromControllerV2(
    sharedApplication: NSApplication.shared,
    controller: nil,
    loadingStatusDelegate: nil,
    openURL: { url in NSWorkspace.shared.open(url) },
    scopeRequest: ScopeRequest(scopeType: .user, scopes: ["files.content.write"])
)

// After auth
let client = DropboxClientsManager.authorizedClient!
client.files.upload(path: "/Watchdawg/\(recording.filename)", input: recording.url)
    .response { response, error in }
```

**References:**
- [SwiftyDropbox](https://github.com/dropbox/SwiftyDropbox)
- [Dropbox Swift Documentation](https://www.dropbox.com/developers/documentation/swift)

---

### 11. iCloud Drive Integration
**Complexity:** ⭐⭐ Medium
**Value:** High

Simplest cloud option for Apple users - no OAuth needed.

**Implementation:**
- Enable iCloud capability in Xcode
- Use `FileManager.default.url(forUbiquityContainerIdentifier:)`
- Copy recordings to iCloud container

```swift
if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
    .appendingPathComponent("Documents/Watchdawg") {
    try FileManager.default.copyItem(at: recording.url, to: iCloudURL.appendingPathComponent(recording.filename))
}
```

**Note:** Requires Apple Developer account with iCloud entitlement.

---

## Phase 5: Advanced (2-4 weeks each)

### 12. Multiple Camera Support
**Complexity:** ⭐⭐⭐ Hard
**Value:** Medium

Support multiple USB/built-in cameras simultaneously.

**Implementation:**
- Enumerate all `AVCaptureDevice` with `.video` type
- Create separate `AVCaptureSession` per camera
- Grid view to show all feeds
- Independent recording per camera

```swift
let devices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
    mediaType: .video,
    position: .unspecified
).devices
```

---

### 13. Two-Way Audio
**Complexity:** ⭐⭐ Medium
**Value:** Medium

Speak through the camera (requires external speaker).

**Implementation:**
- Already capturing audio input
- Add `AVAudioEngine` for output
- Add "Talk" button that plays audio through default output device
- Would need a speaker at the camera location

---

### 14. Web Dashboard / Remote Access
**Complexity:** ⭐⭐⭐⭐ Very Hard
**Value:** Very High

View live feed and recordings from phone/browser.

**Implementation options:**
1. **Local network only:** Run HTTP server (Vapor/Swifter), stream HLS
2. **Internet access:** Use Tailscale/ZeroTier for secure tunnel
3. **Full cloud:** Build companion iOS app + server infrastructure

```swift
// Local HTTP server example using Swifter
let server = HttpServer()
server["/live"] = { request in
    return .raw(200, "OK", ["Content-Type": "video/mp4"]) { writer in
        // Stream current recording chunk
    }
}
server.start(8080)
```

---

### 15. Continuous (24/7) Recording with Timeline
**Complexity:** ⭐⭐⭐ Hard
**Value:** High

Like Ring's 24/7 recording - scrub through entire day.

**Implementation:**
- Record continuously in 1-minute chunks
- Build timeline UI with thumbnails
- Implement efficient seeking across chunks
- Would need significant storage management

---

## Summary: Recommended Order

| Priority | Feature | Complexity | Impact |
|----------|---------|------------|--------|
| 1 | Sentry Mode (Motion Detection) | ⭐⭐ | Very High |
| 2 | Local Push Notifications | ⭐ | High |
| 3 | Configurable Retention | ⭐ | Medium |
| 4 | Person Detection | ⭐⭐⭐ | Very High |
| 5 | iCloud Drive Sync | ⭐⭐ | High |
| 6 | Activity Zones | ⭐⭐ | High |
| 7 | Scheduled Recording | ⭐ | Medium |
| 8 | Google Drive Integration | ⭐⭐⭐ | High |
| 9 | Dropbox Integration | ⭐⭐⭐ | High |
| 10 | Recording Export/Share | ⭐ | Medium |
| 11 | Multiple Cameras | ⭐⭐⭐ | Medium |
| 12 | Familiar Faces | ⭐⭐⭐ | High |
| 13 | Web Dashboard | ⭐⭐⭐⭐ | Very High |

---

## Inspiration Sources

- [Ring Camera Features](https://ring.com/announcements)
- [Frigate NVR](https://frigate.video/) - Local AI object detection
- [ZoneMinder](https://zoneminder.com/) - Full-featured open source NVR
- [Motion Project](https://motion-project.github.io/) - Lightweight motion detection
- [Kerberos.io](https://kerberos.io/) - Modular video analytics

---

## Tech Stack Summary

| Feature | Library/Framework |
|---------|-------------------|
| Motion Detection | Core Image + Accelerate (frame diff) |
| Person Detection | Vision framework or YOLOv8 CoreML |
| Face Recognition | Vision + VNFaceObservation |
| Notifications | UserNotifications |
| Google Drive | swift-google-drive-client |
| Dropbox | SwiftyDropbox |
| iCloud | FileManager ubiquity container |
| Local Server | Swifter or Vapor |
