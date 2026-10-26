import SwiftUI

/// Discover's radius control: the shared slider bound to the app-wide radius.
struct RadiusControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        RadiusSlider(miles: $model.radiusMiles)
    }
}
