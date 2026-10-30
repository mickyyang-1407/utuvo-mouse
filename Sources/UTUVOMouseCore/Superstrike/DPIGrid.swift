// Adapted from jwake/nanostrike (MIT). See LICENSES/Nanostrike-MIT.txt.
/// One band of the sensor's DPI range, within which only multiples of `step`
/// above `lowerBound` are valid.
public struct DPIRange: Hashable, Sendable {
    public let lowerBound: UInt16
    public let upperBound: UInt16
    public let step: UInt16

    public init(lowerBound: UInt16, upperBound: UInt16, step: UInt16) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.step = step
    }

    public func contains(_ dpi: UInt16) -> Bool {
        guard step > 0, dpi >= lowerBound, dpi <= upperBound else { return false }
        return (dpi - lowerBound) % step == 0
    }
}

/// Every DPI the sensor will accept, as bands of coarsening granularity.
///
/// The sensor does not accept arbitrary numbers: it reports a series of ranges,
/// each with its own step. On the G Pro X2 Superstrike that is 100–44,000 DPI,
/// in steps of 1 at the bottom and 200 at the top. Offering a value off this
/// grid means the device rejects the write, or silently stores something the
/// user did not choose.
///
/// See `docs/04-features-2201-2202-dpi.md`.
public struct DPIGrid: Hashable, Sendable {
    public let ranges: [DPIRange]

    public init(ranges: [DPIRange]) {
        self.ranges = ranges
    }

    public var bounds: ClosedRange<UInt16>? {
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return first.lowerBound ... last.upperBound
    }

    public func contains(_ dpi: UInt16) -> Bool {
        ranges.contains { $0.contains(dpi) }
    }

    /// Sorted finite values for a stepper. Shared band boundaries appear once.
    public var values: [Int] {
        Array(Set(ranges.filter { $0.step > 0 && $0.lowerBound <= $0.upperBound }.flatMap { range in
            stride(from: Int(range.lowerBound), through: Int(range.upperBound), by: Int(range.step))
        })).sorted()
    }

    /// Decodes the paginated byte stream `0x2202 getSensorDpiRanges` returns.
    ///
    /// The payloads of successive range indices concatenate into one continuous
    /// stream of big-endian `uint16`s — a value that spans a page boundary is
    /// split across two responses, so they cannot be parsed independently. A
    /// word of the form `0xE0nn` is not a DPI but a **step marker**, setting the
    /// granularity for the values that follow; `0x0000` ends the list.
    ///
    /// - Note: the `0xE0` prefix convention is **DERIVED** from its position and
    ///   effect. It is unambiguous in practice here because `0xE0nn` is 57344 and
    ///   up, far above this sensor's 44,000 ceiling.
    public init(decodingRangeStream bytes: [UInt8]) {
        var words: [UInt16] = []
        var index = 0
        while index + 1 < bytes.count {
            words.append(UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
            index += 2
        }

        var ranges: [DPIRange] = []
        var lower: UInt16?
        var step: UInt16?
        for word in words {
            if word == 0 { break }
            if word & 0xFF00 == 0xE000 {
                step = word & 0x00FF
                continue
            }
            if let lowerBound = lower, let currentStep = step, word > lowerBound {
                ranges.append(
                    DPIRange(lowerBound: lowerBound, upperBound: word, step: currentStep)
                )
            }
            lower = word
        }
        self.ranges = ranges
    }
}

