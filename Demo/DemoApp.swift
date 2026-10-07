import SeatEntitlements
import SeatEntitlementsUI
import SwiftUI

/// The demo app owns every product decision the library deliberately leaves
/// open: which features exist, which fail open or closed, how long state
/// stays fresh, how long an offline device keeps working after a seat moves,
/// and how a 5,000-seat rollout is spread. The library only enforces them.
@main
struct DemoApp: App {
    private let script: ConsoleScript
    private let initialTab: SeatConsoleView.Tab

    init() {
        // `-scenario offlineReassign` / `-tab herd` on the command line land
        // the app on a specific state (used for the CI screenshots).
        let defaults = UserDefaults.standard
        script = defaults.string(forKey: "scenario").flatMap(ConsoleScript.init(rawValue:)) ?? .fresh
        initialTab = defaults.string(forKey: "tab").flatMap(SeatConsoleView.Tab.init(rawValue:)) ?? .access
    }

    var body: some Scene {
        WindowGroup {
            SeatConsoleView(scenario: DemoConfiguration.scenario, script: script, initialTab: initialTab)
        }
    }
}

enum DemoConfiguration {
    static let suite: ProductGroupID = "com.example.classroom.pro"
    static let start = Date(timeIntervalSince1970: 1_792_659_600) // Thu 22 Oct 2026, 09:00 UTC

    static let features = [
        Feature(id: "docs", displayName: "Open class notebooks", group: suite, failureMode: .failOpen),
        Feature(id: "export", displayName: "Export graded PDF", group: suite, failureMode: .failClosed),
        Feature(id: "ai", displayName: "AI feedback (server compute)", group: suite, failureMode: .failClosed),
    ]

    /// Fresh for 6 hours; fail-open features keep working 72 hours past that
    /// when offline. Worst-case offline revocation latency: 78 hours.
    static let policy = GracePolicy(freshFor: 6 * 3_600, offlineGrace: 72 * 3_600, clockSkewTolerance: 300)

    /// Refresh every 6 hours at this device's slot in a 1-hour window;
    /// failures back off 30 s, 60 s, 120 s … capped at 10 minutes, full jitter.
    static let scheduler = RefreshScheduler(interval: 6 * 3_600, spreadWindow: 3_600,
                                            backoffBase: 30, backoffCap: 600)

    static let scenario = SeatConsoleScenario(
        context: CheckContext(userID: "alice", deviceID: "ipad-cart-07"),
        features: features,
        initialSeats: [
            SeatEvent(seatID: "VPP-0042", group: suite, version: 1, state: .assigned(.user("alice")),
                      source: .server, issuedAt: start, expiresAt: start.addingTimeInterval(365 * 86_400)),
            SeatEvent(seatID: "VPP-0043", group: suite, version: 1, state: .assigned(.device("ipad-cart-12")),
                      source: .server, issuedAt: start, expiresAt: start.addingTimeInterval(365 * 86_400)),
        ],
        primarySeat: "VPP-0042",
        reassignTarget: .user("carol"),
        policy: policy,
        scheduler: scheduler,
        herd: HerdScenario(devices: 5_000, capacityPerBucket: 250, bucketSeconds: 10, horizonBuckets: 720),
        startDate: start
    )
}
