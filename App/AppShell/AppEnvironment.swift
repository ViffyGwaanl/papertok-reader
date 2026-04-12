import PTCore
import PTAIServices

struct AppEnvironment {
    let database: AppDatabase
    let calendarService: any CalendarServiceProtocol
    let remindersService: any RemindersServiceProtocol
}
