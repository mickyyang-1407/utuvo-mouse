import Testing
import UTUVOMouseCore
import UTUVOMouseSupport

@Suite("Mouse icon shape families")
struct MouseShapeFamilyTests {
    @Test("verified models always get their own shape")
    func verifiedModels() {
        #expect(MouseShapeFamily.family(model: .mxMaster4, productName: "anything") == .ergoThumbRest)
        #expect(MouseShapeFamily.family(model: .superstrike, productName: "") == .esportsSymmetric)
        #expect(MouseShapeFamily.family(model: .receiver, productName: "") == .receiver)
    }

    @Test("reported names map to the right silhouette", arguments: [
        ("MX Master 3S", MouseShapeFamily.ergoThumbRest),
        ("MX Anywhere 3", .compact),
        ("MX Ergo", .thumbTrackball),
        ("ERGO M575", .thumbTrackball),
        ("MX Vertical", .vertical),
        ("Lift Vertical Ergonomic Mouse", .vertical),
        ("Pebble Mouse 2 M350s", .flatPebble),
        ("G502 X PLUS", .angular),
        ("G600 MMO Gaming Mouse", .sideGrid),
        ("G703 LIGHTSPEED", .esportsErgo),
        ("PRO X SUPERLIGHT 2", .esportsSymmetric),
        ("G305", .esportsSymmetric),
        ("Signature M650", .compact),
        ("M185", .standardOval),
        ("USB Receiver", .receiver),
        ("Some Future Mouse", .standardOval),
    ])
    func nameMapping(name: String, expected: MouseShapeFamily) {
        #expect(MouseShapeFamily.family(model: .unknown, productName: name) == expected)
    }

    @Test("catalog product IDs win over the reported name")
    func productIDs() {
        // MX Master 3S over Bluetooth (B034) and G502 over USB (C08B), per Solaar.
        #expect(MouseShapeFamily.family(model: .unknown, productName: "Mouse", productID: 0xB034) == .ergoThumbRest)
        #expect(MouseShapeFamily.family(model: .unknown, productName: "", productID: 0xC08B) == .angular)
    }

    @Test("names match as whole words only")
    func wholeWords() {
        #expect(MouseShapeFamily.containsWords("mx master 3s", "mx master 3s"))
        #expect(!MouseShapeFamily.containsWords("m905", "m90"))
        #expect(MouseShapeFamily.containsWords("logitech g305 lightspeed", "g305"))
    }
}
