import Foundation
import Testing
@testable import KeepUp

struct RunningChartSamplingTests {
    private func point(_ id: Int, segment: Int, value: Double) -> RunningMetricPoint {
        RunningMetricPoint(id: id, segmentIndex: segment, timestamp: Date(timeIntervalSince1970: Double(id)),
                           timeOffsetSeconds: Double(id), value: value)
    }

    @Test func boundsLargeSeriesAndRetainsSegmentEndpointsAndExtrema() {
        let points = (0..<12_000).map { index in
            point(index, segment: index / 4_000, value: index % 401 == 0 ? 500 : index % 397 == 0 ? -80 : Double(index % 37))
        }
        let sampled = RunningChartSampling.points(points)
        #expect(sampled.count <= 500)
        #expect(sampled.count == Set(sampled.map(\.id)).count)
        for segment in 0..<3 {
            let original = points.filter { $0.segmentIndex == segment }
            let reduced = sampled.filter { $0.segmentIndex == segment }
            #expect(reduced.first == original.first)
            #expect(reduced.last == original.last)
            #expect(reduced.map(\.value).max() == original.map(\.value).max())
            #expect(reduced.map(\.value).min() == original.map(\.value).min())
            #expect(reduced.map(\.id) == reduced.map(\.id).sorted())
            #expect(reduced.allSatisfy { original.contains($0) })
        }
    }

    @Test func neverDropsPauseSegmentsAndLeavesSmallSeriesUntouched() {
        let short = (0..<20).map { point($0, segment: $0 / 10, value: Double($0)) }
        #expect(RunningChartSampling.points(short) == short)
        let fragmented = (0..<1_200).map { point($0, segment: $0 / 6, value: Double($0 % 6)) }
        let sampled = RunningChartSampling.points(fragmented, budget: 500)
        #expect(sampled.count <= 800)
        #expect(Set(sampled.map(\.segmentIndex)) == Set(fragmented.map(\.segmentIndex)))
        for segment in 0..<200 {
            #expect(sampled.contains { $0.id == segment * 6 })
            #expect(sampled.contains { $0.id == segment * 6 + 5 })
        }
    }
}
