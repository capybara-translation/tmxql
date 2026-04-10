import XCTest

final class TMXParserTests: XCTestCase {

    private func parse(_ xml: String) throws -> TMXDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).tmx")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try TMXParser().parse(contentsOf: url)
    }

    private func wrap(_ body: String, srclang: String = "EN") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <tmx version="1.4">
          <header creationtool="test" creationtoolversion="1.0"
                  segtype="sentence" o-tmf="test" adminlang="en-us"
                  srclang="\(srclang)" datatype="plaintext"/>
          <body>
          \(body)
          </body>
        </tmx>
        """
    }

    // MARK: - Basic

    func testBasicTU() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.srclang, "EN")
        XCTAssertEqual(doc.languages, ["EN", "JA"])
        XCTAssertEqual(doc.units.count, 1)

        let unit = doc.units[0]
        XCTAssertEqual(unit.tuid, "tu1")
        XCTAssertEqual(unit.segments["EN"], "Hello")
        XCTAssertEqual(unit.segments["JA"], "こんにちは")
        XCTAssertNil(unit.note)
    }

    func testMultipleTUs() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
            <tu tuid="tu2">
              <tuv xml:lang="EN"><seg>Goodbye</seg></tuv>
              <tuv xml:lang="JA"><seg>さようなら</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.units.count, 2)
        XCTAssertEqual(doc.units[0].tuid, "tu1")
        XCTAssertEqual(doc.units[1].tuid, "tu2")
        XCTAssertEqual(doc.units[1].segments["EN"], "Goodbye")
    }

    func testThreeLanguages() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="FR"><seg>Bonjour</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.languages.count, 3)
        XCTAssertEqual(doc.languages[0], "EN")
        XCTAssertTrue(doc.languages.contains("FR"))
        XCTAssertTrue(doc.languages.contains("JA"))

        let unit = doc.units[0]
        XCTAssertEqual(unit.segments["FR"], "Bonjour")
    }

    // MARK: - srclang ordering

    func testSrclangIsFirstColumn() throws {
        // TUVs appear in order: JA, EN — but srclang is EN
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.languages[0], "EN", "srclang should be first in languages")
    }

    func testSrclangCaseInsensitive() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="en"><seg>Hello</seg></tuv>
              <tuv xml:lang="ja"><seg>こんにちは</seg></tuv>
            </tu>
        """, srclang: "EN")
        let doc = try parse(xml)

        XCTAssertEqual(doc.languages[0], "en", "case-insensitive match for srclang")
    }

    // MARK: - Note

    func testNote() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <note>Greeting message</note>
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.units[0].note, "Greeting message")
    }

    func testTuvNote() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN">
                <note>English note</note>
                <seg>Hello</seg>
              </tuv>
              <tuv xml:lang="JA">
                <note>Japanese note</note>
                <seg>こんにちは</seg>
              </tuv>
            </tu>
        """)
        let doc = try parse(xml)
        let unit = doc.units[0]

        XCTAssertEqual(unit.tuvNotes["EN"], "English note")
        XCTAssertEqual(unit.tuvNotes["JA"], "Japanese note")
        XCTAssertNil(unit.note)
    }

    func testTuAndTuvNoteCoexist() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <note>TU-level note</note>
              <tuv xml:lang="EN">
                <note>EN note</note>
                <seg>Hello</seg>
              </tuv>
              <tuv xml:lang="JA">
                <seg>こんにちは</seg>
              </tuv>
            </tu>
        """)
        let doc = try parse(xml)
        let unit = doc.units[0]

        XCTAssertEqual(unit.note, "TU-level note")
        XCTAssertEqual(unit.tuvNotes["EN"], "EN note")
        XCTAssertTrue(unit.tuvNotes["JA"] == nil)
    }

    // MARK: - Missing segment

    func testMissingSegmentForLanguage() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
            <tu tuid="tu2">
              <tuv xml:lang="EN"><seg>World</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.languages, ["EN", "JA"])
        XCTAssertNil(doc.units[1].segments["JA"])
    }

    // MARK: - Inline tags

    func testInlineTagBptEpt() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg><bpt i="1">&lt;b&gt;</bpt>Bold<ept i="1">&lt;/b&gt;</ept></seg></tuv>
              <tuv xml:lang="JA"><seg><bpt i="1">&lt;b&gt;</bpt>太字<ept i="1">&lt;/b&gt;</ept></seg></tuv>
            </tu>
        """)
        let unit = try parse(xml).units[0]

        XCTAssertTrue(unit.segments["EN"]!.contains("<bpt i=\"1\">"))
        XCTAssertTrue(unit.segments["EN"]!.contains("</bpt>"))
        XCTAssertTrue(unit.segments["EN"]!.contains("<ept i=\"1\">"))
        XCTAssertTrue(unit.segments["EN"]!.contains("</ept>"))
    }

    func testInlineTagPh() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Hello <ph>{0}</ph>, welcome</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは <ph>{0}</ph>、ようこそ</seg></tuv>
            </tu>
        """)
        let unit = try parse(xml).units[0]

        XCTAssertEqual(unit.segments["EN"], "Hello <ph>{0}</ph>, welcome")
    }

    func testInlineTagIt() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg><it pos="begin">&lt;i&gt;</it>italic</seg></tuv>
            </tu>
        """)
        let unit = try parse(xml).units[0]

        XCTAssertTrue(unit.segments["EN"]!.contains("<it pos=\"begin\">"))
    }

    func testInlineTagHi() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg><hi>highlighted</hi> text</seg></tuv>
            </tu>
        """)
        let unit = try parse(xml).units[0]

        XCTAssertEqual(unit.segments["EN"], "<hi>highlighted</hi> text")
    }

    // MARK: - Edge cases

    func testXMLEntities() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>A &amp; B &lt;C&gt;</seg></tuv>
              <tuv xml:lang="JA"><seg>A &amp; B &lt;C&gt;</seg></tuv>
            </tu>
        """)
        let unit = try parse(xml).units[0]

        XCTAssertEqual(unit.segments["EN"], "A & B <C>")
        XCTAssertEqual(unit.segments["JA"], "A & B <C>")
    }

    func testMultilineText() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Line 1
        Line 2
        Line 3</seg></tuv>
            </tu>
        """)
        let unit = try parse(xml).units[0]

        XCTAssertTrue(unit.segments["EN"]!.contains("\n"))
    }

    func testEmptyBody() throws {
        let xml = wrap("")
        let doc = try parse(xml)

        XCTAssertEqual(doc.units.count, 0)
        XCTAssertEqual(doc.languages.count, 0)
    }

    func testMissingTuid() throws {
        let xml = wrap("""
            <tu>
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.units[0].tuid, "")
    }

    func testSrclangAllStar() throws {
        // srclang="*all*" means any language can be source
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tmx version="1.4">
          <header creationtool="test" creationtoolversion="1.0"
                  segtype="sentence" o-tmf="test" adminlang="en-us"
                  srclang="*all*" datatype="plaintext"/>
          <body>
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
          </body>
        </tmx>
        """
        let doc = try parse(xml)

        XCTAssertEqual(doc.srclang, "*all*")
        // When srclang is *all*, no language gets priority — discovery order preserved
        XCTAssertEqual(doc.languages[0], "EN")
    }

    func testLanguageDiscoveryAcrossMultipleTUs() throws {
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
            <tu tuid="tu2">
              <tuv xml:lang="EN"><seg>Goodbye</seg></tuv>
              <tuv xml:lang="FR"><seg>Au revoir</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.languages.count, 3)
        XCTAssertEqual(doc.languages[0], "EN")
        XCTAssertTrue(doc.languages.contains("JA"))
        XCTAssertTrue(doc.languages.contains("FR"))
    }

    func testTuSrclangOverride() throws {
        let xml = wrap("""
            <tu tuid="tu1" srclang="JA">
              <tuv xml:lang="EN"><seg>Hello</seg></tuv>
              <tuv xml:lang="JA"><seg>こんにちは</seg></tuv>
            </tu>
            <tu tuid="tu2">
              <tuv xml:lang="EN"><seg>Goodbye</seg></tuv>
              <tuv xml:lang="JA"><seg>さようなら</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        // tu1 has srclang override to JA
        XCTAssertEqual(doc.units[0].srclang, "JA")
        // tu2 inherits header srclang (nil means use header)
        XCTAssertNil(doc.units[1].srclang)
    }

    func testDuplicateLanguageInTUV() throws {
        // If a tu has two tuv with same lang, last one wins
        let xml = wrap("""
            <tu tuid="tu1">
              <tuv xml:lang="EN"><seg>First</seg></tuv>
              <tuv xml:lang="EN"><seg>Second</seg></tuv>
              <tuv xml:lang="JA"><seg>日本語</seg></tuv>
            </tu>
        """)
        let doc = try parse(xml)

        XCTAssertEqual(doc.units[0].segments["EN"], "Second")
    }
}
