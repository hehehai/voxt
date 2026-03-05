import Foundation

enum AppLocalization {
    static var language: AppInterfaceLanguage {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.interfaceLanguage)
        return AppInterfaceLanguage(rawValue: raw ?? "") ?? .system
    }

    static var locale: Locale {
        language.locale
    }

    static func localizedString(_ key: String) -> String {
        let identifier = language.localeIdentifier
        if let localized = localizedString(key, localeIdentifier: identifier) {
            return localized
        }
        if let english = localizedString(key, localeIdentifier: "en") {
            return english
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localizedString(key), locale: locale, arguments: arguments)
    }

    private static func localizedString(_ key: String, localeIdentifier: String) -> String? {
        guard let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return nil
        }
        let value = bundle.localizedString(forKey: key, value: key, table: nil)
        if localeIdentifier == "en" {
            return value
        }
        return value == key ? nil : value
    }
}
