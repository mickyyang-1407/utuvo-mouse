import UTUVOMouseCore

/// Top-view silhouettes for the shapes Logitech mice come in.
///
/// Original vector drawings, simplified from public dimensions and photos:
/// no product image, logo or trademark artwork is used.
public enum MouseShapeFamily: String, CaseIterable, Sendable {
    case ergoThumbRest       // MX Master
    case compact             // MX Anywhere, M-series small
    case flatPebble          // Pebble, POP
    case vertical            // MX Vertical, Lift
    case thumbTrackball      // MX Ergo, M575
    case esportsSymmetric    // PRO / Superlight / Superstrike / G305
    case esportsErgo         // G403 / G703 / G903
    case angular             // G502
    case sideGrid            // G600
    case standardOval        // M185, G102, office mice
    case receiver            // LIGHTSPEED / Bolt / Unifying receiver

    /// Picks a family from the model and the name the device reported.
    public static func family(model: MouseModel, productName: String?, productID: Int? = nil) -> MouseShapeFamily {
        switch model {
        case .mxMaster4: return .ergoThumbRest
        case .superstrike: return .esportsSymmetric
        case .receiver: return .receiver
        case .unknown: break
        }
        // 1. The product ID macOS reports (USB or Bluetooth), from the catalog.
        if let productID, let family = catalogProductIDs[productID] { return family }
        let name = (productName ?? "").lowercased()
        // 2. A catalog name, matched as whole words.
        if let match = catalogNames.first(where: { containsWords(name, $0.0) }) { return match.1 }
        // 3. Series keywords, for models newer than the catalog.
        func has(_ needles: String...) -> Bool { needles.contains { name.contains($0) } }
        if has("receiver", "接收器", "bolt", "unifying") { return .receiver }
        if has("mx master", "m720", "triathlon", "g604", "m705", "marathon") { return .ergoThumbRest }
        if has("vertical", "lift") { return .vertical }
        if has("mx ergo", "m575", "trackball", "m570") { return .thumbTrackball }
        if has("pebble", "pop mouse", "pop ") { return .flatPebble }
        if has("g502") { return .angular }
        if has("g600") { return .sideGrid }
        if has("g403", "g703", "g903", "g705", "g402") { return .esportsErgo }
        if has("superlight", "pro x", "pro wireless", "g pro", "g305", "g304", "g309", "g303", "superstrike", "pro 2") {
            return .esportsSymmetric
        }
        if has("anywhere", "m650", "signature", "m590", "m330", "m331", "m350", "m240", "m196", "m220") { return .compact }
        if has("m185", "m190", "m170", "m171", "b100", "m100", "g102", "g203", "m90", "m110") { return .standardOval }
        return .standardOval
    }

    /// True when `needle` appears in `haystack` with no letter or digit glued to either side.
    public static func containsWords(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: searchRange) {
            let before = found.lowerBound == haystack.startIndex ? nil : haystack[haystack.index(before: found.lowerBound)]
            let after = found.upperBound == haystack.endIndex ? nil : haystack[found.upperBound]
            let glued: (Character?) -> Bool = { $0.map { $0.isLetter || $0.isNumber } ?? false }
            if !glued(before) && !glued(after) { return true }
            searchRange = found.upperBound..<haystack.endIndex
        }
        return false
    }
}
