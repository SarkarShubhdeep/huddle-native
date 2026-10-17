import Testing
@testable import HuddleKit

@Suite("RichMarkdown")
struct RichMarkdownTests {
    private let people = RichMarkdown.mentionTokens([(id: "u1", name: "Alex Kim"), (id: "u2", name: "Sam Lee")])

    @Test("Inline styles are written as GitHub markdown")
    func inlineStyles() {
        let doc = RichDocument([RichBlock(.paragraph, [
            RichRun("Ship "), RichRun("the fix", bold: true), RichRun(" "),
            RichRun("today", italic: true), RichRun(", not "), RichRun("Friday", strike: true),
            RichRun(" and "), RichRun("this", bold: true, italic: true),
        ])])
        #expect(RichMarkdown.markdown(from: doc) == "Ship **the fix** *today*, not ~~Friday~~ and ***this***")
    }

    @Test("Spaces stay outside the markers")
    func spacesOutside() {
        let doc = RichDocument([RichBlock(.paragraph, [RichRun("a"), RichRun(" bold ", bold: true), RichRun("b")])])
        #expect(RichMarkdown.markdown(from: doc) == "a **bold** b")
    }

    @Test("Neighbouring runs with the same style merge")
    func mergesRuns() {
        let doc = RichDocument([RichBlock(.paragraph, [RichRun("one ", bold: true), RichRun("two", bold: true)])])
        #expect(RichMarkdown.markdown(from: doc) == "**one two**")
    }

    @Test("Lists: bullets, numbers that count up, and checklists")
    func lists() {
        let doc = RichDocument([
            RichBlock(.paragraph, [RichRun("Today:")]),
            RichBlock(.bullet, [RichRun("standup")]),
            RichBlock(.numbered, [RichRun("first")]),
            RichBlock(.numbered, [RichRun("second")]),
            RichBlock(.checklist(done: false), [RichRun("ship it")]),
            RichBlock(.checklist(done: true), [RichRun("review")]),
        ])
        let md = RichMarkdown.markdown(from: doc)
        #expect(md == "Today:\n- standup\n1. first\n2. second\n- [ ] ship it\n- [x] review")
        #expect(RichMarkdown.document(from: md) == doc)
    }

    @Test("Literal markdown characters are escaped and read back")
    func escaping() {
        let doc = RichDocument([RichBlock(.paragraph, [RichRun("2*3 = 6 and snake_case ~~ok")])])
        let md = RichMarkdown.markdown(from: doc)
        #expect(md == #"2\*3 = 6 and snake\_case \~\~ok"#)
        #expect(RichMarkdown.document(from: md) == doc)
    }

    @Test("People are written as @Firstname, collected, and read back as mentions")
    func personMentions() {
        let doc = RichDocument([RichBlock(.paragraph, [
            RichRun("Pairing with "), RichRun("@Alex Kim", mention: .person(userId: "u1")),
            RichRun(" on "), RichRun("Fix login", mention: .ticket(ticketId: "k1")),
        ])])
        let md = RichMarkdown.markdown(from: doc)
        #expect(md == "Pairing with @Alex on Fix login")
        #expect(doc.mentionedUserIds == ["u1"])
        #expect(doc.firstTicketId == "k1")

        let back = RichMarkdown.document(from: "Ask @alex and @sam, not email@x.com or @nobody", people: people)
        let mentions = back.blocks[0].runs.compactMap(\.mention)
        #expect(mentions == [.person(userId: "u1"), .person(userId: "u2")])
        #expect(back.blocks[0].plainText == "Ask @alex and @sam, not email@x.com or @nobody")
    }

    @Test("A first name two teammates share is not a mention token")
    func ambiguousNames() {
        let tokens = RichMarkdown.mentionTokens([(id: "a", name: "Sam Lee"), (id: "b", name: "Sam Park"), (id: "c", name: "Rae")])
        #expect(tokens == ["rae": "c"])
    }

    @Test("Markdown typed by hand reads into styles")
    func reads() {
        let doc = RichMarkdown.document(from: "**Bold** _it_ and ~~gone~~ plus a lone * star")
        let runs = doc.blocks[0].runs
        #expect(runs.first == RichRun("Bold", bold: true))
        #expect(runs.contains(RichRun("it", italic: true)))
        #expect(runs.contains(RichRun("gone", strike: true)))
        #expect(doc.blocks[0].plainText == "Bold it and gone plus a lone * star")
    }

    @Test("Round trip of a mixed post is stable")
    func roundTrip() {
        let md = "**Plan**\n- [ ] Finish *iPad* fix with @Alex\n- [x] ~~Old task~~\n1. one\n2. two\n\nThanks"
        let doc = RichMarkdown.document(from: md, people: people)
        #expect(RichMarkdown.markdown(from: doc) == md)
        #expect(doc.mentionedUserIds == ["u1"])
    }

    @Test("Links keep their target, inside other styles, and round-trip")
    func links() {
        let md = "*Started [#ce05f: Huddle ticket](/app/tickets/0c26)*"
        let doc = RichMarkdown.document(from: md)
        let runs = doc.blocks[0].runs
        #expect(runs.map(\.text).joined() == "Started #ce05f: Huddle ticket")
        #expect(runs.last == RichRun("#ce05f: Huddle ticket", italic: true, link: "/app/tickets/0c26"))
        #expect(RichMarkdown.markdown(from: doc) == "*Started* *[#ce05f: Huddle ticket](/app/tickets/0c26)*")
        // A bracket that isn't a link stays text.
        #expect(RichMarkdown.document(from: "see [notes] later").blocks[0].plainText == "see [notes] later")
    }

    @Test("Trailing spaces are dropped from each line")
    func trailingSpaces() {
        let doc = RichDocument([RichBlock(.checklist(done: false), [RichRun("Review "), RichRun("Fix", mention: .ticket(ticketId: "k")), RichRun(" ")])])
        #expect(RichMarkdown.markdown(from: doc) == "- [ ] Review Fix")
    }
}
