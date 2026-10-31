import Foundation

/// Looks up text in `Resources/<language>.lproj/Localizable.strings`, keyed by
/// the English text itself. macOS picks the language from the user's whole
/// list of preferred languages, and anything missing falls back to English.
///
/// The folders are copied into the app by `scripts/build-app.sh`. Running the
/// bare binary, outside the app, shows English.
let appDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Picline"

enum InterfaceLanguage {
    static var current: String? {
        get {
            UserDefaults.standard.string(forKey: "interfaceLanguage")
                ?? Bundle.main.object(forInfoDictionaryKey: "PiclineDefaultLanguage") as? String
        }
        set { UserDefaults.standard.set(newValue ?? "system", forKey: "interfaceLanguage") }
    }
}

func L(_ english: String) -> String {
    var bundle = Bundle.main
    if let language = InterfaceLanguage.current, language != "system",
       let path = bundle.path(forResource: language, ofType: "lproj"), let localized = Bundle(path: path) {
        bundle = localized
    }
    return bundle.localizedString(forKey: english, value: english, table: nil)
        .replacingOccurrences(of: "Picline", with: appDisplayName)
}
