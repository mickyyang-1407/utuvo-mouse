import Foundation
import UTUVOMouseCore
import UTUVOMouseIO

/// Routed before AppLocalization, --probe or UTUVOMouseApp.main(). Diagnostics
/// are fixed bilingual text plus an allowlisted code; no device/error text leaks.
enum CapabilityInspectionCommand {
    static let help = """
    Read-only developer inspection / 開發者唯讀檢查
      --inspect-capabilities 046d-b025-bluetooth --allow-read-only-hidpp
      --inspect-capabilities --help

    Explicit consent opens only 046D:B025 Bluetooth, without seizure.
    明確同意後只開啟 046D:B025 Bluetooth，不獨佔裝置。
    Queries protocol version and feature IDs; configuration writes stay disabled.
    僅查詢協定版本與功能 ID；設定寫入維持停用。
    """

    static func run() async -> Int32 {
        do {
            let report = try await MXAnywhere3InspectionService.inspect(consent: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return 0
        } catch {
            reportFailure(error)
            return 1
        }
    }

    static func reportFailure(_ error: any Error) {
        let code = (error as? CapabilityInspectionError) ?? .transportFailure
        let message = "utuvo-mouse: inspection failed / 唯讀檢查失敗 [\(code.rawValue)]\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
