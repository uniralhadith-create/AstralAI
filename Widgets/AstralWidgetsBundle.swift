import WidgetKit
import SwiftUI

/// Entry point of the widget extension: the home-screen status widget and
/// the agent Live Activity (Lock Screen + Dynamic Island).
@main
struct AstralWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AgentStatusWidget()
        AgentLiveActivityWidget()
    }
}
