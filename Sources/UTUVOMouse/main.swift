import Foundation
import UTUVOMouseCore
import UTUVOMouseIO
import UTUVOMouseLocalization
import UTUVOMouseSupport

let arguments = Array(CommandLine.arguments.dropFirst())

// Consume the file import intent before any normal app setup, before the
// inspection command and before the broader --probe handling. Mixed modes and
// malformed arguments exit here, without touching a device.
do {
    switch try CapabilityImportInvocation.parse(arguments) {
    case .notRequested: break
    case .help:
        print(CapabilityImportCommand.help)
        exit(0)
    case .importCapabilities(let file, let directory):
        exit(CapabilityImportCommand.run(file: file, supportDirectory: directory))
    }
} catch {
    CapabilityImportCommand.reportFailure(error)
    exit(2)
}

// Consume inspection intent before any normal app setup or broader --probe
// handling. Missing consent, mixed modes and malformed arguments exit here.
do {
    switch try CapabilityInspectionInvocation.parse(arguments) {
    case .notRequested: break
    case .help:
        print(CapabilityInspectionCommand.help)
        exit(0)
    case .inspect:
        exit(await CapabilityInspectionCommand.run())
    }
} catch {
    CapabilityInspectionCommand.reportFailure(error)
    exit(2)
}

#if DEBUG
// Isolated native design fixture. Production builds ignore these bundle keys.
if Bundle.main.object(forInfoDictionaryKey: "UTUVOMouseDemoFixture") as? Bool == true {
    LaunchOptions.demoMode = true
    if let language = Bundle.main.object(forInfoDictionaryKey: "UTUVOMouseFixtureLanguage") as? String {
        LaunchOptions.languageOverride = MouseLanguage(rawValue: language)
    }
}
#endif

if arguments.contains("--demo") {
    LaunchOptions.demoMode = true
}
if let index = arguments.firstIndex(of: "--language"), index + 1 < arguments.count {
    LaunchOptions.languageOverride = MouseLanguage(rawValue: arguments[index + 1])
}
if arguments.contains("--localization-check") {
    for language in [MouseLanguage.english, .traditionalChinese] {
        let localizer = MouseLocalizer(language: language)
        print("\(language.rawValue)\t\(localizer.resourceBundleURL.path)\t\(localizer.string("app.title"))\t\(localizer.string("language.section"))")
    }
    exit(0)
}
AppLocalization.configure(demoMode: LaunchOptions.demoMode)

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    \(AppLocalization.text("app.title"))

      --probe    \(AppLocalization.text("cli.help.probe"))
      --demo     \(AppLocalization.text("cli.help.demo"))
      --language en|zh-Hant  \(AppLocalization.text("cli.help.language"))
      --localization-check  \(AppLocalization.text("cli.help.localizationCheck"))
      --help     \(AppLocalization.text("cli.help.help"))

    \(AppLocalization.text("cli.help.normal"))
    """)
    exit(0)
}

if arguments.contains("--probe") {
    exit(await ProbeCommand.run())
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

#if DEBUG
if let value = Bundle.main.object(forInfoDictionaryKey: "UTUVOMouseFixtureAppearance") as? String {
    LaunchOptions.appearance = value == "dark" ? .dark : .light
}
#endif

UTUVOMouseApp.main()
