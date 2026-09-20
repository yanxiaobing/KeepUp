import CoreLocation
import Foundation
import Testing
@testable import KeepUp

@Test func runningMapMatchesExternalForwardCoordinateFixtures() {
    // Independent reference values from eviltransform go/transform_test.go at
    // 03ba58d92dfda57f8a1635f3805483c8fc10bd77, also used by PunchCard's migration tests.
    let fixtures: [(Double, Double, Double, Double)] = [
        (31.1774276, 121.5272106, 31.17530398364597, 121.531541859215),
        (22.543847, 113.912316, 22.540796131694766, 113.9171764808363),
        (39.911954, 116.377817, 39.91334545536069, 116.38404722455657)
    ]
    for (latitude, longitude, expectedLatitude, expectedLongitude) in fixtures {
        let original = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let display = RunningMapCoordinates.displayCoordinate(forWGS84: original)
        #expect(abs(display.latitude - expectedLatitude) < 0.000005)
        #expect(abs(display.longitude - expectedLongitude) < 0.000005)
        #expect(original.latitude == latitude && original.longitude == longitude)
    }
}

@Test func runningMapPreservesNeighboringRegionsAndInvalidCoordinates() {
    // Several of these lie within the old coarse China rectangle.
    let unchanged: [(Double, Double)] = [
        (35.6762, 139.6503), (37.5665, 126.9780), (21.0285, 105.8542),
        (27.7172, 85.3240), (47.9189, 106.9172), (22.3193, 114.1694),
        (22.1987, 113.5439), (25.0330, 121.5654), (51.5074, -0.1278),
        (1.3521, 103.8198), (0, 0), (91, 110), (30, 181), (30, .infinity)
    ]
    for (latitude, longitude) in unchanged {
        let point = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        #expect(!RunningMapCoordinates.containsMainland(point))
        let display = RunningMapCoordinates.displayCoordinate(forWGS84: point)
        #expect(display.latitude == latitude && display.longitude == longitude)
    }
    let invalid = CLLocationCoordinate2D(latitude: .nan, longitude: 110)
    #expect(!RunningMapCoordinates.containsMainland(invalid))
    #expect(RunningMapCoordinates.displayCoordinate(forWGS84: invalid).latitude.isNaN)
    #expect(RunningMapCoordinates.containsMainland(.init(latitude: 20.02, longitude: 110.35)))
}

@Test func runningMapLatitudeIndexPreservesSourcePolygonMembership() throws {
    struct Source: Decodable { let vertices: [[Double]]; let rings: [[Int]] }
    let source = try BundledJSON.decode(Source.self, named: "running-map-region")
    // An unindexed ring walk is an independent oracle for bucket-edge mistakes.
    func reference(_ latitude: Double, _ longitude: Double) -> Bool {
        var polygons = Set<Int>()
        for ring in source.rings {
            var inside = false
            for offset in 0..<ring[1] {
                let a = source.vertices[ring[0] + offset]
                let b = source.vertices[ring[0] + (offset + ring[1] - 1) % ring[1]]
                if (a[1] > latitude) != (b[1] > latitude), longitude < (b[0] - a[0]) * (latitude - a[1]) / (b[1] - a[1]) + a[0] { inside.toggle() }
            }
            if inside {
                if polygons.contains(ring[2]) { polygons.remove(ring[2]) }
                else { polygons.insert(ring[2]) }
            }
        }
        return !polygons.isEmpty
    }
    for latitude in stride(from: 16.0, through: 53.0, by: 1.0) {
        for longitude in stride(from: 74.0, through: 134.0, by: 2.0) {
            for offset in [-0.0000001, 0, 0.0000001] {
                let point = CLLocationCoordinate2D(latitude: latitude + offset, longitude: longitude)
                #expect(RunningMapCoordinates.containsMainland(point) == reference(point.latitude, point.longitude))
            }
        }
    }
}
