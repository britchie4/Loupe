import Foundation
import CoreGraphics

/// Represents a region selected by the user containing multiple elements
public struct SelectionRegion: Identifiable {
    public let id: UUID
    public let boundingBox: CGRect
    public let elements: [AXElementInfo]
    public let screenshotData: Data?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        elements: [AXElementInfo],
        screenshotData: Data? = nil
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.elements = elements
        self.screenshotData = screenshotData
        self.createdAt = Date()
    }

    /// The number of elements in this region
    public var elementCount: Int {
        elements.count
    }

    /// Human-readable summary of the region
    public var summary: String {
        if elements.isEmpty {
            return "Empty region"
        } else if elements.count == 1 {
            return "1 element: \(elements[0].displayLabel(style: .humanized))"
        } else {
            let roles = Dictionary(grouping: elements, by: \.role)
                .map { "\($0.value.count) \(ElementKind.name(forRole: $0.key).lowercased())\($0.value.count > 1 ? "s" : "")" }
                .joined(separator: ", ")
            return "\(elements.count) elements: \(roles)"
        }
    }
}
