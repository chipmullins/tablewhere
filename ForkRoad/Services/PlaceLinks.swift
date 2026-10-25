import Foundation
import MapKit
import PickerCore

/// Hand-offs to the phone and Apple Maps.
enum PlaceLinks {

    /// tel: link with everything but digits and + stripped out.
    static func phoneURL(_ place: Place) -> URL? {
        guard let raw = place.phoneNumber else { return nil }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    /// Opens Apple Maps with driving directions to the place.
    static func openDirections(_ place: Place) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.phoneNumber = place.phoneNumber
        item.url = place.websiteURL
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
