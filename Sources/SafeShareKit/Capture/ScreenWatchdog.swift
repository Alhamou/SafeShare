import AppKit
import Combine

@MainActor
public protocol ScreenWatchdogDelegate: AnyObject {
    func screenWatchdogDidDetectScreenSleep()
    func screenWatchdogDidDetectScreenWake()
    func screenWatchdogDidDetectScreenLock()
    func screenWatchdogDidDetectScreenUnlock()
    func screenWatchdogDidChangeScreenParameters()
}

@MainActor
public final class ScreenWatchdog {
    public weak var delegate: ScreenWatchdogDelegate?

    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    public init(delegate: ScreenWatchdogDelegate? = nil) {
        self.delegate = delegate
        startMonitoring()
    }

    public func startMonitoring() {
        stopMonitoring()

        let wsCenter = NSWorkspace.shared.notificationCenter

        // 1. Screens Sleep / Wake
        let sleepObs = wsCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.delegate?.screenWatchdogDidDetectScreenSleep()
            }
        }
        observers.append(sleepObs)

        let wakeObs = wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.delegate?.screenWatchdogDidDetectScreenWake()
            }
        }
        observers.append(wakeObs)

        // 2. Screen Lock / Unlock (Distributed Notifications)
        let distCenter = DistributedNotificationCenter.default()
        let lockObs = distCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.delegate?.screenWatchdogDidDetectScreenLock()
            }
        }
        distributedObservers.append(lockObs)

        let unlockObs = distCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.delegate?.screenWatchdogDidDetectScreenUnlock()
            }
        }
        distributedObservers.append(unlockObs)

        // 3. Screen parameters changed (Monitor connect/disconnect/resolution change)
        let paramObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.delegate?.screenWatchdogDidChangeScreenParameters()
            }
        }
        observers.append(paramObs)
    }

    public func stopMonitoring() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in observers {
            wsCenter.removeObserver(obs)
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()

        let distCenter = DistributedNotificationCenter.default()
        for obs in distributedObservers {
            distCenter.removeObserver(obs)
        }
        distributedObservers.removeAll()
    }

    deinit {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in observers {
            wsCenter.removeObserver(obs)
            NotificationCenter.default.removeObserver(obs)
        }
        let distCenter = DistributedNotificationCenter.default()
        for obs in distributedObservers {
            distCenter.removeObserver(obs)
        }
    }
}
