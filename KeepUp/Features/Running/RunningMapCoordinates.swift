import CoreLocation
import Foundation

/// Presentation only: storage, distances and GPS filtering always use the original WGS-84 fixes.
/// Call once at the MapKit boundary, never on an already converted display coordinate.
enum RunningMapCoordinates {
    static func displayCoordinate(forWGS84 coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard containsMainland(coordinate) else { return coordinate }
        // Forward transform adapted from eviltransform (BSD-2-Clause). The complete
        // redistribution notice and pinned polygon provenance ship in running-map-region.json.
        let x = coordinate.longitude - 105, y = coordinate.latitude - 35
        let rootX = sqrt(abs(x)), xy = x * y
        let common = 20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)
        var latitude = common + 20 * sin(y * .pi) + 40 * sin(y * .pi / 3)
        latitude += 160 * sin(y * .pi / 12) + 320 * sin(y * .pi / 30)
        var longitude = common + 20 * sin(x * .pi) + 40 * sin(x * .pi / 3)
        longitude += 150 * sin(x * .pi / 12) + 300 * sin(x * .pi / 30)
        latitude = latitude * 2 / 3 - 100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * xy + 0.2 * rootX
        longitude = longitude * 2 / 3 + 300 + x + 2 * y + 0.1 * x * x + 0.1 * xy + 0.1 * rootX
        let radians = coordinate.latitude * .pi / 180
        let eccentricity = 0.00669342162296594323
        let magic = 1 - eccentricity * pow(sin(radians), 2), root = sqrt(magic)
        latitude = latitude * 180 / ((6_378_137 * (1 - eccentricity)) / (magic * root) * .pi)
        longitude = longitude * 180 / (6_378_137 / root * cos(radians) * .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + latitude, longitude: coordinate.longitude + longitude)
    }

    static func containsMainland(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate), coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (15.775377...53.569444).contains(coordinate.latitude),
              (73.602256...134.772579).contains(coordinate.longitude) else { return false }
        // The rectangle only avoids unnecessary work; membership uses all 70 exact
        // source polygons, including islands, rather than shifting neighboring countries.
        let bucket = Int(floor(coordinate.latitude))
        var inside = Set<Int>()
        for edge in region.edgesByLatitude[bucket] ?? [] {
            let a = edge.a, b = edge.b
            if (a.latitude > coordinate.latitude) != (b.latitude > coordinate.latitude),
               coordinate.longitude < (b.longitude - a.longitude) * (coordinate.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                if inside.contains(edge.polygon) { inside.remove(edge.polygon) }
                else { inside.insert(edge.polygon) }
            }
        }
        return !inside.isEmpty
    }

    private struct PolygonData: Decodable {
        let version: Int
        let vertices: [[Double]] // longitude, latitude; original seven decimal places
        let rings: [[Int]] // first vertex, vertex count, polygon id
    }
    private struct Edge {
        let a: CLLocationCoordinate2D
        let b: CLLocationCoordinate2D
        let polygon: Int
    }
    private struct Region {
        let edgesByLatitude: [Int: [Edge]]
        init(_ source: PolygonData) {
            var buckets: [Int: [Edge]] = [:]
            for ring in source.rings {
                let start = ring[0], count = ring[1]
                for offset in 0..<count {
                    let a = source.vertices[start + offset]
                    let b = source.vertices[start + (offset + count - 1) % count]
                    let edge = Edge(a: .init(latitude: a[1], longitude: a[0]),
                                    b: .init(latitude: b[1], longitude: b[0]), polygon: ring[2])
                    for bucket in Int(floor(min(a[1], b[1])))...Int(floor(max(a[1], b[1]))) {
                        buckets[bucket, default: []].append(edge)
                    }
                }
            }
            edgesByLatitude = buckets
        }
    }
    private static let region = Region(BundledJSON.required(PolygonData.self, named: "running-map-region") { data in
        guard data.version == 1, data.vertices.count == 14_118, data.rings.count == 70,
              data.vertices.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) && (-180...180).contains($0[0]) && (-90...90).contains($0[1]) }),
              data.rings.allSatisfy({ $0.count == 3 && $0[0] >= 0 && $0[1] >= 3 && $0[0] <= data.vertices.count - $0[1] && (0..<70).contains($0[2]) }) else {
            throw BundledJSON.ConfigurationError.invalid("running-map-region: vertices or rings")
        }
    })
}
