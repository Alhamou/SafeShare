# SafeShare Security & Privacy Policy

SafeShare is engineered with privacy as a foundational primitive. It is designed to prevent accidental information disclosure during remote screen sharing sessions on macOS.

---

## 1. Core Privacy Guarantees

### 100% Offline by Design
- SafeShare makes **zero network requests**.
- The binary contains no analytics, telemetry, remote pings, or crash reporting services.
- SafeShare does not require, request, or use network access entitlements.

### Zero-Persistence Frame Pipeline
- Video frames captured via `ScreenCaptureKit` are processed directly in GPU memory using `AVSampleBufferDisplayLayer` hardware acceleration.
- No screen frames, screenshots, or pixel buffers are ever written to disk or persistent storage.
- All in-memory frame buffers (`CMSampleBuffer`) are released immediately after presentation.

### Fail-Closed Architecture
- If an interruption occurs (display sleep, screen lock, permission revocation, or filter reconfiguration delay), SafeShare immediately enters a **Fail-Closed Privacy Blanking** state.
- In this state, the Safe View output is instantly replaced with a solid opaque privacy surface (`#0B132B`) to guarantee that un-filtered frames never leak into conference calls.

---

## 2. macOS Permissions & TCC

SafeShare requires exactly one system permission:
- **Screen & System Audio Recording (`kTCCServiceScreenCapture`)**: Required by Apple's `ScreenCaptureKit` API to discover running applications and capture the desktop stream.

SafeShare does **not** require:
- Accessibility permissions (`AXIsProcessTrusted`).
- Full Disk Access.
- Kernel extensions, system extensions, or root privileges.

---

## 3. Reporting Security Vulnerabilities

If you identify a security or privacy vulnerability in SafeShare, please report it responsibly:
1. Open a private security advisory on the GitHub repository, or
2. Contact the maintainers directly.

All reports will be addressed promptly with coordinated vulnerability disclosure.
