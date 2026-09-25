import MapKit
import UIKit

/// Injectable boundary: unit tests never request network maps.
@MainActor protocol RunningShareSnapshotSource {
    func snapshot(route: RunningShareRoute, size: CGSize, satellite: Bool,
                  presentation: RunningMapPresentation) async -> UIImage?
}

struct RunningMapCameraState {
    let center: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let heading: CLLocationDirection
    let pitch: CGFloat
    let visibleRect: MKMapRect

    var snapshotCamera: MKMapCamera {
        MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: pitch, heading: heading)
    }
}

struct RunningMapPresentation {
    var camera: RunningMapCameraState? = nil
    var showsKilometers = false
    var showsPlaces = true

    static func kilometerPoints(session: RunningSession) -> [RunningPoint] {
        var distance = 0.0
        var points: [RunningPoint] = []
        for segment in session.segments {
            for (previous, point) in zip(segment, segment.dropFirst()) {
                distance += previous.distance(to: point)
                while distance >= Double(points.count + 1) * 1_000, points.count < session.splits.count {
                    points.append(point)
                }
            }
        }
        return points
    }
}

struct RunningShareRoute {
    let segments: [[CLLocationCoordinate2D]]
    let coloredSegments: [([CLLocationCoordinate2D], UInt32)]
    let kilometerPoints: [CLLocationCoordinate2D]
    var isEmpty: Bool { segments.allSatisfy(\.isEmpty) }

    init(session: RunningSession) {
        kilometerPoints = RunningMapPresentation.kilometerPoints(session: session).map {
            RunningMapCoordinates.displayCoordinate(forWGS84: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }
        let average = RunningMetrics(session: session).averageSpeedKilometersPerHour.map { $0 / 3.6 } ?? 0
        coloredSegments = session.segments.flatMap { segment in
            zip(segment, segment.dropFirst()).compactMap { previous, point in
                let raw = [previous, point].map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                guard raw.allSatisfy(CLLocationCoordinate2DIsValid) else { return nil }
                let duration = point.timestamp.timeIntervalSince(previous.timestamp)
                let speed = duration > 0 ? previous.distance(to: point) / duration : 0
                let hex: UInt32 = speed <= 1.94 ? 0xA2E36E : speed > average ? 0xFF9457 : 0xFFDF48
                return (raw.map { RunningMapCoordinates.displayCoordinate(forWGS84: $0) }, hex)
            }
        }
        segments = session.segments.map { segment in
            segment.compactMap { point in
                let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                guard point.latitude.isFinite, point.longitude.isFinite, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                return RunningMapCoordinates.displayCoordinate(forWGS84: coordinate)
            }
        }.filter { !$0.isEmpty }
    }

    /// Unwrap around the first route point so crossing ±180° doesn't produce a world-wide map.
    var projectedSegments: [[MKMapPoint]] {
        let world = MKMapRect.world.size.width
        var previousX: Double?
        return segments.map { segment in
            segment.map { coordinate in
                var point = MKMapPoint(coordinate)
                if let previousX { point.x += ((previousX - point.x) / world).rounded() * world }
                previousX = point.x
                return point
            }
        }
    }

    func mapRect(for size: CGSize) -> MKMapRect {
        let points = projectedSegments.flatMap { $0 }
        guard let first = points.first else { return .world }
        let minX = points.map(\.x).min() ?? first.x, maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y, maxY = points.map(\.y).max() ?? first.y
        let minimum = MKMapPointsPerMeterAtLatitude(segments.first?.first?.latitude ?? 0) * 250
        var width = max(minimum, maxX - minX) * 1.4
        var height = max(minimum, maxY - minY) * 1.6
        let aspect = size.width / max(1, size.height)
        if width / height < aspect { width = height * aspect } else { height = width / aspect }
        // Leave space for Apple's attribution along the bottom of the snapshot.
        return MKMapRect(x: (minX + maxX - width) / 2, y: (minY + maxY - height) / 2 + height * 0.03, width: width, height: height)
    }
}

@MainActor final class SystemRunningShareSnapshotSource: RunningShareSnapshotSource {
    func snapshot(route: RunningShareRoute, size: CGSize, satellite: Bool,
                  presentation: RunningMapPresentation) async -> UIImage? {
        guard !route.isEmpty, !Task.isCancelled else { return nil }
        let options = MKMapSnapshotter.Options()
        if let camera = presentation.camera {
            if abs(camera.heading) > 1 || camera.pitch > 1 {
                options.camera = camera.snapshotCamera
            } else {
                // A flat map's visible rect preserves the user's pan and zoom across poster sizes.
                options.mapRect = camera.visibleRect
            }
        } else {
            options.mapRect = route.mapRect(for: size)
        }
        options.size = size
        options.scale = 2
        options.mapType = satellite ? .satellite : .standard
        options.pointOfInterestFilter = presentation.showsPlaces ? .includingAll : .excludingAll
        options.showsBuildings = true
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let request = RunningSnapshotRequest(options: options, route: route, presentation: presentation)
        return await withTaskCancellationHandler {
            await request.start()
        } onCancel: {
            Task { @MainActor in request.cancel() }
        }
    }
}

@MainActor private final class RunningSnapshotRequest {
    private let snapshotter: MKMapSnapshotter
    private let route: RunningShareRoute
    private let presentation: RunningMapPresentation
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var deadline: Task<Void, Never>?
    private var completed = false

    init(options: MKMapSnapshotter.Options, route: RunningShareRoute, presentation: RunningMapPresentation) {
        snapshotter = MKMapSnapshotter(options: options)
        self.route = route
        self.presentation = presentation
    }

    func start() async -> UIImage? {
        guard !Task.isCancelled, !completed else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                self?.cancel()
            }
            // Unlike start(with:completionHandler:), this SDK overload declares its
            // callback NS_SWIFT_UI_ACTOR and defaults to the main queue. The snapshot
            // remains on that actor while its pixels and projected coordinates are read.
            snapshotter.start { [weak self] snapshot, _ in
                guard let self, !self.completed else { return }
                self.finish(snapshot.map { snapshot in
                    RunningShareMapDrawing.draw(size: snapshot.image.size, base: snapshot.image, route: self.route,
                                                presentation: self.presentation) {
                        snapshot.point(for: $0)
                    }
                })
            }
        }
    }

    func cancel() {
        finish(nil)
        snapshotter.cancel()
    }

    private func finish(_ image: UIImage?) {
        guard !completed else { return }
        completed = true
        deadline?.cancel()
        deadline = nil
        continuation?.resume(returning: image)
        continuation = nil
    }
}

@MainActor enum RunningShareMapDrawing {
    static func schematic(route: RunningShareRoute, size: CGSize, locale: Locale,
                          presentation: RunningMapPresentation = .init()) -> UIImage {
        let rect = presentation.camera?.visibleRect ?? route.mapRect(for: size)
        let world = MKMapRect.world.size.width
        let centerX = rect.midX
        let image = draw(size: size, base: nil, route: route, presentation: presentation) { coordinate in
            var point = MKMapPoint(coordinate)
            point.x += ((centerX - point.x) / world).rounded() * world
            return CGPoint(x: (point.x - rect.minX) / rect.size.width * size.width,
                           y: (point.y - rect.minY) / rect.size.height * size.height)
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: .zero)
            let text = localized("runningShare.schematic", locale) as NSString
            text.draw(in: CGRect(x: 12, y: size.height - 25, width: size.width - 24, height: 22), withAttributes: [
                .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.secondaryLabel
            ])
        }
    }

    static func draw(size: CGSize, base: UIImage?, route: RunningShareRoute,
                     presentation: RunningMapPresentation = .init(),
                     project: (CLLocationCoordinate2D) -> CGPoint) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let base { base.draw(in: CGRect(origin: .zero, size: size)) }
            else {
                UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            context.cgContext.saveGState()
            context.cgContext.clip(to: CGRect(x: 0, y: 0, width: size.width, height: max(0, size.height - 30)))
            UIColor(red: 1, green: 0.39, blue: 0.25, alpha: 1).setStroke()
            for (segment, hex) in route.coloredSegments {
                UIColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1).setStroke()
                let path = UIBezierPath(); path.lineWidth = 5; path.lineCapStyle = .round; path.lineJoinStyle = .round
                for (index, coordinate) in segment.enumerated() {
                    if index == 0 { path.move(to: project(coordinate)) } else { path.addLine(to: project(coordinate)) }
                }
                path.stroke()
            }
            func marker(_ coordinate: CLLocationCoordinate2D?, color: UIColor, asset: String) {
                guard let coordinate else { return }
                let center = project(coordinate)
                if let image = UIImage(named: asset) {
                    image.draw(in: CGRect(x: center.x - 12.5, y: center.y - 12.5, width: 25, height: 25))
                    return
                }
                let circle = UIBezierPath(ovalIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
                color.setFill(); circle.fill(); UIColor.white.setStroke(); circle.lineWidth = 2; circle.stroke()
            }
            marker(route.segments.first?.first, color: .systemGreen, asset: "run_result_start")
            marker(route.segments.last?.last, color: .systemOrange, asset: "run_result_end")
            if presentation.showsKilometers {
                for (index, coordinate) in route.kilometerPoints.enumerated() {
                    let center = project(coordinate)
                    let circle = UIBezierPath(ovalIn: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
                    UIColor(red: 1, green: 100 / 255, blue: 64 / 255, alpha: 1).setFill()
                    circle.fill()
                    let number = String(index + 1) as NSString
                    let font = UIFont.systemFont(ofSize: 12, weight: .bold)
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                    let textSize = number.size(withAttributes: attributes)
                    number.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
                                withAttributes: attributes)
                }
            }
            context.cgContext.restoreGState()
        }
    }
}
