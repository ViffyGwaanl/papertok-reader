import SwiftUI

struct RootScene: View {
    let environment: AppEnvironment
    @Binding var showMigration: Bool

    var body: some View {
        MainTabView(
            database: environment.database,
            calendarService: environment.calendarService,
            remindersService: environment.remindersService
        )
        .sheet(isPresented: $showMigration) {
            MigrationProgressView(database: environment.database)
        }
    }
}
