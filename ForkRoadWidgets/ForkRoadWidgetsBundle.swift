import SwiftUI
import WidgetKit

@main
struct ForkRoadWidgetsBundle: WidgetBundle {
    var body: some Widget {
        widgets()
    }

    /// A plain function, not a result builder: an `if #available` inside the
    /// `@WidgetBundleBuilder` body drops every widget on iOS 17 with the
    /// Xcode 16.0 SDK (fixed in 16.1), so the OS check happens out here.
    private func widgets() -> some Widget {
        if #available(iOSApplicationExtension 18.0, *) {
            return widgetsWithControls
        } else {
            return baseWidgets
        }
    }

    @WidgetBundleBuilder
    private var baseWidgets: some Widget {
        TonightsPickWidget()
        GroupPlanLiveActivity()
    }

    @available(iOSApplicationExtension 18.0, *)
    @WidgetBundleBuilder
    private var widgetsWithControls: some Widget {
        TonightsPickWidget()
        GroupPlanLiveActivity()
        SpinControl()
    }
}
