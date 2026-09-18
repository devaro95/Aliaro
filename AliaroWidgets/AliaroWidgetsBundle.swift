import WidgetKit
import SwiftUI

@main
struct AliaroWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RemindersWidget()
        FamilyCalendarWidget()
        TodayMenuWidget()
    }
}
