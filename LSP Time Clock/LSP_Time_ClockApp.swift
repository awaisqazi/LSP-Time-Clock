//
//  LSP_Time_ClockApp.swift
//  LSP Time Clock
//

import SwiftUI
import SwiftData

@main
struct LSP_Time_ClockApp: App {
    @State private var coordinator: AppCoordinator
    @State private var syncEngine: SyncEngine

    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            Employee.self,
            PunchLog.self,
            PendingDeletion.self,
            KioskMessage.self,
            MessageReceipt.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        sharedModelContainer = container

        let coordinator = AppCoordinator()
        let engine = SyncEngine(container: container)
        // Returning to the Idle screen is the cheapest natural moment to
        // sync: nobody is mid-punch, and it happens after every single
        // interaction the kiosk supports. Debounced inside the engine.
        coordinator.onReturnHome = { [weak engine] in
            engine?.requestSync()
        }

        _coordinator = State(initialValue: coordinator)
        _syncEngine = State(initialValue: engine)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .environment(syncEngine)
                .task {
                    // Launch sync: un-debounced so a kiosk that was rebooted
                    // after an offline stretch uploads immediately.
                    await syncEngine.syncNow()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
