import Foundation
import UTUVOMouseCore
import UTUVOMouseIO

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    UTUVO Mouse

      --probe    唯讀掃描：列出 HID++ 裝置與可讀到的狀態，輸出 JSON。不寫入任何設定。
      --demo     以合成資料啟動介面（畫面會明確標示為示範模式）。
      --help     顯示這段說明。

    介面模式（不帶參數）會連接實際裝置。
    """)
    exit(0)
}

if arguments.contains("--probe") {
    exit(await ProbeCommand.run())
}

if arguments.contains("--demo") {
    LaunchOptions.demoMode = true
}

// Developer only: check the layout in one appearance without touching the
// system setting.
if let index = arguments.firstIndex(of: "--appearance"), index + 1 < arguments.count {
    switch arguments[index + 1] {
    case "dark": LaunchOptions.appearance = .dark
    case "light": LaunchOptions.appearance = .light
    default: break
    }
}

UTUVOMouseApp.main()
