@testable import Bisky
import XCTest

private let bisky = "https://bisky.ai"

/// `text` per language, since 2.6.0 (Fixtures/text_v2.json).
@MainActor
final class TextTests: XCTestCase {
    private func text(_ data: [String: Any]) -> BiskyText {
        let labels = data["labels"] as? [String: Any]
        return BiskyText(
            locale: data["locale"] as? String,
            welcomeTitle: data["welcomeTitle"] as? String,
            placeholder: data["placeholder"] as? String,
            labels: labels.map { BiskyText.Labels(checkout: $0["checkout"] as? String) }
        )
    }

    private func data(_ json: String) throws -> NSDictionary {
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
        return try XCTUnwrap(sent["data"] as? NSDictionary)
    }

    func testBuildsEveryMessageOfTheFixture() throws {
        for message in try Fixture.list("text_v2", "hostToPage") {
            let expected = try XCTUnwrap(message["data"] as? [String: Any])
            let sent = try data(HostMessage.text(text(expected)).json())
            XCTAssertEqual(sent, expected as NSDictionary)
        }
    }

    func testKeepsOneSetPerLocaleAndSendsThemAllAfterAReload() async throws {
        let controller = BiskyAgentController(organization: "adcoop", locale: "ar-AE")
        controller.sleep = { _ in }
        let web = FakeWebView()
        controller.attach(web)
        for message in try Fixture.list("text_v2", "hostToPage") {
            XCTAssertTrue(controller.setText(text(try XCTUnwrap(message["data"] as? [String: Any]))))
        }
        XCTAssertTrue(controller.setText(BiskyText(locale: "ar-AE", placeholder: "اسألنا")))
        XCTAssertFalse(controller.setText(BiskyText(locale: "arabic please", welcomeTitle: "x")))
        controller.receive(try Fixture.page("ready"), isMainFrame: true, origin: bisky)
        await until { web.delivered.count == 4 }

        web.delivered.removeAll()
        controller.didStartLoading()
        controller.receive(try Fixture.page("ready", ["id": "ready-2"]), isMainFrame: true, origin: bisky)
        await until { web.types.filter { $0 == "text" }.count == 3 }
        let texts = try zip(web.types, web.delivered).filter { $0.0 == "text" }.map { try data($0.1) }
        let kept = try XCTUnwrap(Fixture.object("text_v2")["kept"] as? [String: Any])
        var expected = kept.filter { $0.key != "$comment" }
        var arabic = try XCTUnwrap(expected["ar-AE"] as? [String: Any])
        arabic["placeholder"] = "اسألنا"
        expected["ar-AE"] = arabic
        let sets = Dictionary(uniqueKeysWithValues: texts.compactMap { set -> (String, NSDictionary)? in
            guard set["welcomeTitle"] != nil || set["placeholder"] != nil else { return nil }
            let mutable = NSMutableDictionary(dictionary: set)
            let locale = mutable["locale"] as? String ?? ""
            mutable.removeObject(forKey: "locale")
            return (locale, mutable)
        })
        XCTAssertEqual(sets.count, 3)
        for (locale, words) in expected {
            XCTAssertEqual(sets[locale], words as? NSDictionary, locale)
        }
    }

    func testTheViewsWordsFollowTheLocale() {
        XCTAssertEqual(BiskyViewWords.forLocale("ar-AE"), .arabic)
        XCTAssertEqual(BiskyViewWords.forLocale("fr_FR"), .french)
        XCTAssertEqual(BiskyViewWords.forLocale("tr"), .english)
        XCTAssertEqual(BiskyViewWords.forLocale(nil), .english)
    }
}
