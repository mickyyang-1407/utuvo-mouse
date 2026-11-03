import Testing
import UTUVOMouseIO

@Suite("Receiver link notifications")
struct ReceiverLinkNotificationTests {
    @Test("0x41 with bit 6 clear means the paired mouse is linked")
    func linked() {
        let state = IOKitHIDTransport.linkState(of: [0x10, 0x01, 0x41, 0x0C, 0x02, 0xA8, 0xC0])
        #expect(state?.index == 0x01)
        #expect(state?.linked == true)
    }

    @Test("0x41 with bit 6 set means the link is not established (asleep or off)")
    func notLinked() {
        #expect(IOKitHIDTransport.linkState(of: [0x10, 0x01, 0x41, 0x0C, 0x42, 0xA8, 0xC0])?.linked == false)
    }

    @Test("other reports are not link notifications")
    func ignored() {
        #expect(IOKitHIDTransport.linkState(of: [0x10, 0x01, 0x00, 0x11, 0x00]) == nil)
        #expect(IOKitHIDTransport.linkState(of: [0x02, 0x01, 0x41, 0x00, 0x00]) == nil)
        #expect(IOKitHIDTransport.linkState(of: [0x10, 0x01, 0x41]) == nil)
    }
}
