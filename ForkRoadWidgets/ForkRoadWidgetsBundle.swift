import SwiftUI
import WidgetKit

@main
struct ForkRoadWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TonightsPickWidget()
        GroupPlanLiveActivity()
        if #available(iOS 18.0, *) {
            SpinControl()
        }
    }
}
