//
//  LSP_Time_ClockApp.swift
//  LSP Time Clock
//

import SwiftUI
import SwiftData

@main
struct LSP_Time_ClockApp: App {
    @State private var coordinator = AppCoordinator()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Employee.self,
            PunchLog.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
        }
        .modelContainer(sharedModelContainer)
    }
}
