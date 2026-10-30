import Foundation

public extension HIDPPClient {
    /// DEVICE_NAME 0x0005: fn0 gives byte length, fn1(offset) gives up to
    /// sixteen UTF-8 bytes. No configuration or friendly-name write is sent.
    func readDeviceName(featureIndex: UInt8) async throws -> String? {
        let header = try await request(featureIndex: featureIndex, function: 0)
        guard let lengthByte = header.first, (1...128).contains(Int(lengthByte)) else { return nil }
        let length = Int(lengthByte)
        var bytes: [UInt8] = []
        while bytes.count < length {
            let fragment = try await request(featureIndex: featureIndex, function: 1, payload: [UInt8(bytes.count)])
            guard !fragment.isEmpty else { return nil }
            bytes.append(contentsOf: fragment.prefix(min(16, length - bytes.count)))
        }
        guard let name = String(bytes: bytes, encoding: .utf8) else { return nil }
        return MouseIdentification.cleanName(name)
    }
}
