import Foundation

/// The view's own words, shown when the chat cannot open. Since 2.6.0.
public struct BiskyViewWords: Sendable, Equatable {
    public let failedTitle: String
    public let failedBody: String
    public let tryAgain: String

    public init(failedTitle: String, failedBody: String, tryAgain: String) {
        self.failedTitle = failedTitle
        self.failedBody = failedBody
        self.tryAgain = tryAgain
    }

    public static let english = BiskyViewWords(
        failedTitle: "The assistant couldn't open",
        failedBody: "Check your connection and try again.",
        tryAgain: "Try again"
    )

    public static let arabic = BiskyViewWords(
        failedTitle: "تعذّر فتح المساعد",
        failedBody: "تحقق من اتصالك وحاول مرة أخرى.",
        tryAgain: "حاول مرة أخرى"
    )

    public static let french = BiskyViewWords(
        failedTitle: "L'assistant n'a pas pu s'ouvrir",
        failedBody: "Vérifiez votre connexion et réessayez.",
        tryAgain: "Réessayer"
    )

    /// The words for a BCP 47 tag: Arabic, French, else English.
    public static func forLocale(_ locale: String?) -> BiskyViewWords {
        let language = locale?.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        switch language {
        case "ar": return arabic
        case "fr": return french
        default: return english
        }
    }
}
