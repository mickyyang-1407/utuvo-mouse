import Foundation
import Testing
import UTUVOMouseLocalization

@Suite("Packaged localization — isolated bundles")
struct PackagedLocaleTests {
    @Test(arguments: ["zh-hant", "zh-Hant"])
    func packagedChineseFolderResolves(identifier: String) throws {
        let root = MouseTestTemporaryRoot.url.appendingPathComponent("locale-\(UUID()).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for language in ["en", identifier] {
            let folder = root.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let value = language == "en" ? "English" : "繁體中文"
            try Data("\"fixture.label\" = \"\(value)\";\n".utf8)
                .write(to: folder.appendingPathComponent("Localizable.strings"), options: .atomic)
        }
        let info = ["CFBundleIdentifier": "fixture.\(UUID())", "CFBundlePackageType": "BNDL", "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: root))
        #expect(MouseLocalizer(language: .traditionalChinese, bundle: bundle).string("fixture.label") == "繁體中文")
        #expect(MouseLocalizer(language: .english, bundle: bundle).string("fixture.label") == "English")
    }
}
