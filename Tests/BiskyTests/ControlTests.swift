import Foundation
@testable import Bisky
import UIKit
import XCTest

private let bisky = "https://bisky.ai"

/// control_v1.json: what an app can do with an open chat beyond its look, since SDK 2.2.0.
final class ControlContractTests: XCTestCase {
    func testParsesEveryPageMessage() throws {
        let messages = try Fixture.list("control_v1", "pageToHost")
        let parsed = try messages.map { message in
            try XCTUnwrap(PageEvent.parse(Fixture.json(message)), "\(message["type"] ?? "?") did not parse")
        }
        XCTAssertEqual(parsed.map(\.id), messages.map { $0["id"] as? String })

        guard case let .message(.ready(ready)) = parsed[0].event else {
            return XCTFail("not ready: \(parsed[0])")
        }
        // Capabilities pass through as the page lists them.
        XCTAssertEqual(ready.capabilities, [
            "cart.snapshot", "session.launch", "theme", "focus", "visibility", "chat.send", "chat.new",
            "basket", "starters", "locale", "restrictions", "state", "history", "memory", "appearance", "text",
        ])
        XCTAssertEqual(
            parsed[1].event,
            .state(BiskyChatState(view: .welcome, busy: false, basketOpen: false, itemCount: 0))
        )
        XCTAssertEqual(
            parsed[2].event,
            .state(BiskyChatState(
                view: .conversation, busy: true, basketOpen: false, itemCount: 3, conversationId: "conv-1"
            ))
        )
        XCTAssertEqual(parsed[2].timestamp, Date(timeIntervalSince1970: 1_791_374_422))
        XCTAssertEqual(
            parsed[3].event,
            .state(BiskyChatState(
                view: .welcome, busy: false, basketOpen: false, itemCount: 0, previousChats: 3, memory: true
            ))
        )
        // `state` is not a case of the 1.0.0 PageMessage, so a switch over it still compiles.
        try XCTAssertNil(PageMessage.parse(Fixture.page("state", in: "control_v1")))
    }

    func testRefusesAStateOfTheWrongShape() throws {
        for data: [String: Any] in [
            ["view": "welcome", "busy": false, "basketOpen": false, "itemCount": -1],
            ["view": "checkout", "busy": false, "basketOpen": false, "itemCount": 0],
            ["view": "welcome", "busy": "no", "basketOpen": false, "itemCount": 0],
            ["view": "welcome", "busy": false, "itemCount": 0],
            ["view": "welcome", "busy": false, "basketOpen": false, "itemCount": 1.5],
        ] {
            try XCTAssertNil(PageEvent.parse(Fixture.page("state", ["data": data], in: "control_v1")), "\(data)")
        }
    }

    func testBuildsEveryHostMessageAsTheFixtureDoes() throws {
        let expected = try Fixture.list("control_v1", "hostToPage")
        XCTAssertEqual(expected.count, 10)
        for envelope in expected {
            let id = try XCTUnwrap(envelope["id"] as? String)
            let at = try Date(timeIntervalSince1970: TimeInterval(XCTUnwrap(envelope["ts"] as? Int64)) / 1000)
            let data = try XCTUnwrap(envelope["data"] as? [String: Any])
            let type = try XCTUnwrap(envelope["type"] as? String)
            let message: HostMessage? = switch type {
            case "chat.send": try .chatSend(XCTUnwrap(data["text"] as? String), id: id, timestamp: at)
            case "chat.new": .chatNew(id: id, timestamp: at)
            case "basket.open": .basketOpen(id: id, timestamp: at)
            case "basket.close": .basketClose(id: id, timestamp: at)
            case "history.open": .historyOpen(id: id, timestamp: at)
            case "memory.open": .memoryOpen(id: id, timestamp: at)
            case "starters":
                try .starters(
                    XCTUnwrap(data["items"] as? [[String: String]]).map {
                        BiskyStarter(label: $0["label"] ?? "", prompt: $0["prompt"])
                    },
                    id: id, timestamp: at
                )
            case "locale": try .locale(XCTUnwrap(data["locale"] as? String), id: id, timestamp: at)
            case "restrictions":
                try .restrictions(
                    XCTUnwrap(data["exclude"] as? [String]).map { try XCTUnwrap(BiskyRestriction(rawValue: $0)) },
                    id: id, timestamp: at
                )
            default: nil
            }
            let built = try XCTUnwrap(message, type)
            XCTAssertEqual(built.type, type)
            let encoded = try JSONSerialization.jsonObject(with: Data(built.json().utf8))
            var fixture = envelope
            fixture["$comment"] = nil
            XCTAssertEqual(encoded as? NSDictionary, fixture as NSDictionary, type)
        }
    }

    func testCannotBuildWhatThePageRefuses() throws {
        let rejected = try Fixture.list("control_v1", "rejected")
        XCTAssertEqual(rejected.map { $0["type"] as? String }, ["chat.send", "restrictions", "locale", "starters"])
        for envelope in rejected {
            let data = try XCTUnwrap(envelope["data"] as? [String: Any])
            switch envelope["type"] as? String {
            case "chat.send":
                try XCTAssertNil(HostMessage.chatSend(XCTUnwrap(data["text"] as? String)))
            case "restrictions":
                // Only the four kinds can be written.
                for kind in try XCTUnwrap(data["exclude"] as? [String]) {
                    XCTAssertNil(BiskyRestriction(rawValue: kind))
                }
            case "locale":
                try XCTAssertNil(HostMessage.locale(XCTUnwrap(data["locale"] as? String)))
            default:
                let items = try XCTUnwrap(data["items"] as? [[String: String]]).map {
                    BiskyStarter(label: $0["label"] ?? "")
                }
                XCTAssertNil(HostMessage.starters(items))
                XCTAssertNotNil(HostMessage.starters(Array(items.prefix(BiskyStarter.maxCount))))
            }
        }
    }

    func testTrimsAndChecksWhatItSends() throws {
        // Trimmed, counted as the page counts (UTF-16), at most 2000.
        let sent = try XCTUnwrap(HostMessage.chatSend("  Milk please \n")).json()
        XCTAssertTrue(sent.contains(#""data":{"text":"Milk please"}"#), sent)
        XCTAssertNotNil(HostMessage.chatSend(String(repeating: "a", count: 2000)))
        XCTAssertNil(HostMessage.chatSend(String(repeating: "a", count: 2001)))
        XCTAssertNil(HostMessage.chatSend(""))

        XCTAssertEqual(BiskyStarter(label: "  Breakfast ", prompt: " Eggs and bread "), BiskyStarter(
            label: "Breakfast", prompt: "Eggs and bread"
        ))
        XCTAssertTrue(BiskyStarter(label: String(repeating: "a", count: 60)).isValid)
        XCTAssertFalse(BiskyStarter(label: String(repeating: "a", count: 61)).isValid)
        XCTAssertFalse(BiskyStarter(label: "  ").isValid)
        XCTAssertFalse(BiskyStarter(label: "Snacks", prompt: " ").isValid)
        XCTAssertFalse(BiskyStarter(label: "Snacks", prompt: String(repeating: "a", count: 301)).isValid)
        XCTAssertNil(HostMessage.starters([BiskyStarter(label: "")]))
        // An empty list brings the retailer's back.
        try XCTAssertTrue(XCTUnwrap(HostMessage.starters([])).json().contains(#""data":{"items":[]}"#))

        for tag in ["ar", "ar-AE", "fr", "zh-Hant-TW", "AR-ae"] {
            XCTAssertTrue(HostMessage.isLocale(tag), tag)
        }
        for tag in ["", "a", "arabic", "ar_AE", "ar-", "ar-A", "arabic please"] {
            XCTAssertFalse(HostMessage.isLocale(tag), tag)
        }

        // Each kind once, the rest by its wire name.
        let restrictions = HostMessage.restrictions([.alcoholFree, .pork, .alcoholFree, .tobacco]).json()
        XCTAssertTrue(restrictions.contains(#""data":{"exclude":["alcohol_free","pork","tobacco"]}"#), restrictions)
        XCTAssertEqual(BiskyRestriction.allCases.map(\.rawValue), ["alcohol", "alcohol_free", "pork", "tobacco"])
    }
}

/// A view showing the chat, recording when the chat asks it to close.
@MainActor
private final class FakePresenter: BiskyChatPresenter {
    var closed = 0

    func closeChat() {
        closed += 1
    }
}

@MainActor
final class ControlControllerTests: XCTestCase {
    private func open(
        starters: [BiskyStarter]? = nil,
        restrictions: [BiskyRestriction]? = nil
    ) -> (BiskyAgentController, FakeWebView) {
        let controller = BiskyAgentController(
            organization: "suppy-demo", store: "branch-7", locale: "en",
            starters: starters, restrictions: restrictions
        )
        controller.sleep = { _ in }
        let web = FakeWebView()
        controller.attach(web)
        return (controller, web)
    }

    private func post(_ controller: BiskyAgentController, _ json: String) {
        controller.receive(json, isMainFrame: true, origin: bisky)
    }

    private func data(_ json: String) throws -> NSDictionary {
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
        return try XCTUnwrap(sent["data"] as? NSDictionary)
    }

    func testSendsEachControlMessageOnceThePageIsReady() async throws {
        let (controller, web) = open()
        XCTAssertTrue(controller.sendMessage(" Snacks for a movie night "))
        controller.newChat()
        controller.openBasket()
        controller.closeBasket()
        controller.openHistory()
        controller.openMemory()
        XCTAssertTrue(controller.setStarters([BiskyStarter(label: "Breakfast for 4")]))
        XCTAssertTrue(controller.setLocale("ar-AE"))
        controller.setRestrictions([.pork])
        await settle()
        XCTAssertEqual(web.delivered, [])

        try post(controller, Fixture.page("ready"))
        await until { web.delivered.count == 9 }
        XCTAssertEqual(web.types, [
            "chat.send", "chat.new", "basket.open", "basket.close", "history.open", "memory.open",
            "starters", "locale", "restrictions",
        ])
        XCTAssertEqual(try data(web.delivered[0]), ["text": "Snacks for a movie night"])
        XCTAssertEqual(try data(web.delivered[1]), [:])
        XCTAssertEqual(try data(web.delivered[4]), [:])
        XCTAssertEqual(try data(web.delivered[6]), ["items": [["label": "Breakfast for 4"]]])
        XCTAssertEqual(try data(web.delivered[7]), ["locale": "ar-AE"])
        XCTAssertEqual(try data(web.delivered[8]), ["exclude": ["pork"]])
    }

    func testRefusesWhatThePageWouldDrop() async throws {
        let (controller, web) = open()
        try post(controller, Fixture.page("ready"))
        XCTAssertFalse(controller.sendMessage("   "))
        XCTAssertFalse(controller.setLocale("arabic please"))
        XCTAssertFalse(controller.setStarters((1 ... 7).map { BiskyStarter(label: "\($0)") }))
        XCTAssertFalse(controller.setStarters([BiskyStarter(label: "")]))
        await settle()
        XCTAssertEqual(web.delivered, [])
        // Nothing was kept either: a reload sends nothing.
        controller.didStartLoading()
        try post(controller, Fixture.page("ready", ["id": "ready-2"]))
        await settle()
        XCTAssertEqual(web.delivered, [])

        controller.dispose()
        XCTAssertFalse(controller.setStarters([]))
        XCTAssertFalse(controller.setLocale("ar"))
        controller.setRestrictions([.alcohol])
        controller.sendMessage("Late")
        await settle()
        XCTAssertEqual(web.delivered, [])
    }

    func testSendsTheOpeningStartersAndRestrictionsOnReady() async throws {
        let (controller, web) = open(
            starters: [BiskyStarter(label: "Iftar essentials", prompt: "I need everything for an iftar for 6 people")],
            restrictions: [.alcohol, .alcoholFree]
        )
        // Never on the chat URL.
        XCTAssertEqual(
            controller.url.absoluteString,
            "\(bisky)/c/suppy-demo?store=branch-7&embed=ios&sdk=\(BiskySDK.version)&locale=en"
        )
        try post(controller, Fixture.page("ready"))
        await until { web.delivered.count == 2 }
        XCTAssertEqual(web.types, ["starters", "restrictions"])
        XCTAssertEqual(try data(web.delivered[0]), [
            "items": [["label": "Iftar essentials", "prompt": "I need everything for an iftar for 6 people"]],
        ])
        XCTAssertEqual(try data(web.delivered[1]), ["exclude": ["alcohol", "alcohol_free"]])
    }

    func testSendsTheKeptStartersRestrictionsAndLocaleAgainOnEveryReady() async throws {
        let (controller, web) = open(starters: [BiskyStarter(label: "Breakfast")], restrictions: [.tobacco])
        try post(controller, Fixture.page("ready"))
        await until { web.delivered.count == 2 }

        // The last of each is what is kept, not a merge.
        controller.setStarters([BiskyStarter(label: "Snacks", prompt: "Snacks for 6")])
        controller.setStarters([BiskyStarter(label: "Dinner")])
        controller.setRestrictions([.pork, .alcohol])
        controller.setLocale("fr")
        controller.setLocale("ar-AE")
        // Not kept: a message, a new chat, the basket.
        controller.sendMessage("Milk")
        controller.newChat()
        controller.openBasket()
        await until { web.delivered.count == 10 }

        // A reload is a new page: it has only what the chat URL says.
        controller.reload()
        controller.didStartLoading()
        await settle()
        XCTAssertEqual(web.delivered.count, 10)
        try post(controller, Fixture.page("ready", ["id": "ready-2"]))
        await until { web.delivered.count == 13 }
        XCTAssertEqual(Array(web.types[10...]), ["locale", "restrictions", "starters"])
        XCTAssertEqual(try data(web.delivered[10]), ["locale": "ar-AE"])
        XCTAssertEqual(try data(web.delivered[11]), ["exclude": ["pork", "alcohol"]])
        XCTAssertEqual(try data(web.delivered[12]), ["items": [["label": "Dinner"]]])

        // An empty list (the retailer's own) is kept too, and so is an empty restriction list.
        controller.setStarters([])
        controller.setRestrictions([])
        await until { web.delivered.count == 15 }
        controller.didStartLoading()
        try post(controller, Fixture.page("ready", ["id": "ready-3"]))
        await until { web.delivered.count == 18 }
        XCTAssertEqual(try data(web.delivered[16]), ["exclude": []])
        XCTAssertEqual(try data(web.delivered[17]), ["items": []])
    }

    func testALocaleOnlyFromTheChatURLIsNotSent() async throws {
        let (controller, web) = open()
        try post(controller, Fixture.page("ready"))
        controller.didStartLoading()
        try post(controller, Fixture.page("ready", ["id": "ready-2"]))
        await settle()
        XCTAssertEqual(web.delivered, [])
    }

    func testCallsOnStateChangeForEveryState() throws {
        let (controller, _) = open()
        var states: [BiskyChatState] = []
        controller.onStateChange = { states.append($0) }
        for message in try Fixture.list("control_v1", "pageToHost") {
            post(controller, Fixture.json(message))
        }
        // At least once: a repeat of the same id is dropped.
        try post(controller, Fixture.page("state", in: "control_v1"))
        XCTAssertEqual(states.map(\.view), [.welcome, .conversation, .welcome])
        XCTAssertEqual(states.map(\.itemCount), [0, 3, 0])
        XCTAssertEqual(states[1].conversationId, "conv-1")
        XCTAssertEqual(states[1].busy, true)
        XCTAssertEqual(states.map(\.previousChats), [nil, nil, 3])
        XCTAssertEqual(states.last?.memory, true)
    }

    func testClosesTheViewShowingTheChatWhenTheAppSetNoOnClose() throws {
        let (controller, _) = open()
        let view = FakePresenter()
        controller.viewShown(by: view, at: Date())
        try post(controller, Fixture.page("close", ["id": "close-1"]))
        XCTAssertEqual(view.closed, 1)

        // The app's onClose decides instead.
        var closes = 0
        controller.onClose = { closes += 1 }
        try post(controller, Fixture.page("close", ["id": "close-2"]))
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(view.closed, 1)

        // A hidden chat closes nothing.
        controller.onClose = nil
        controller.preload()
        controller.viewDismissed(by: view)
        try post(controller, Fixture.page("close", ["id": "close-3"]))
        XCTAssertEqual(view.closed, 1)
    }

    func testTheViewIsASheetOrAFullScreenPage() {
        let (controller, _) = open()
        let sheet = BiskyAgentViewController(controller: controller)
        XCTAssertEqual(sheet.presentation, .sheet)
        XCTAssertEqual(sheet.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(sheet.sheetPresentationController?.prefersGrabberVisible, true)

        let page = BiskyAgentViewController(controller: controller, presentation: .fullScreen)
        XCTAssertEqual(page.presentation, .fullScreen)
        XCTAssertEqual(page.modalPresentationStyle, .fullScreen)
        XCTAssertNil(page.sheetPresentationController)
    }

    func testTheViewClosesWithSwiftUIsDismissOrByPoppingItself() {
        let (controller, _) = open()
        let chat = BiskyAgentViewController(controller: controller, presentation: .fullScreen)
        var dismissed = 0
        chat.dismissChat = { dismissed += 1 }
        chat.closeChat()
        XCTAssertEqual(dismissed, 1)

        // Pushed on a navigation controller: the back arrow pops it.
        let pushed = BiskyAgentViewController(controller: controller)
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(pushed, animated: false)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        pushed.closeChat()
        XCTAssertEqual(navigation.viewControllers.count, 1)

        // Neither presented nor pushed: it stays, for the app's onClose to handle.
        let alone = BiskyAgentViewController(controller: controller)
        alone.closeChat()
        XCTAssertNil(alone.presentingViewController)
    }
}
