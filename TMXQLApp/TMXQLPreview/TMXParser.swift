import Foundation

struct TMXUnit {
    let tuid: String
    let srclang: String?
    let segments: [String: String]
    let note: String?
    let tuvNotes: [String: String]
}

struct TMXDocument {
    let srclang: String
    let languages: [String]
    let units: [TMXUnit]
}

final class TMXParser: NSObject, XMLParserDelegate {

    private var headerSrclang = ""
    private var units: [TMXUnit] = []

    // All languages encountered (preserving discovery order)
    private var languageOrder: [String] = []
    private var languageSet: Set<String> = []

    // Current tu
    private var currentTuid = ""
    private var currentTuSrclang: String?
    private var currentSegments: [String: String] = [:]
    private var currentNote: String?

    // Current tuv
    private var currentLang = ""
    private var currentTuvNote: String?
    private var currentTuvNotes: [String: String] = [:]

    // Parsing state
    private var inTU = false
    private var inTUV = false
    private var inSeg = false
    private var inNote = false
    private var currentText = ""

    // Inline elements rendered as visible tag markers
    private static let visibleInlineElements: Set<String> = [
        "bpt", "ept", "ph", "it", "hi", "sub", "ut"
    ]

    func parse(contentsOf url: URL) throws -> TMXDocument {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false

        resetState()

        guard parser.parse() else {
            if let error = parser.parserError {
                throw error
            }
            throw NSError(domain: "TMXParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse TMX"])
        }

        let orderedLanguages = buildLanguageOrder()
        return TMXDocument(srclang: headerSrclang,
                           languages: orderedLanguages,
                           units: units)
    }

    private func resetState() {
        headerSrclang = ""
        units = []
        languageOrder = []
        languageSet = []
        currentTuid = ""
        currentTuSrclang = nil
        currentSegments = [:]
        currentNote = nil
        currentLang = ""
        currentTuvNote = nil
        currentTuvNotes = [:]
        inTU = false
        inTUV = false
        inSeg = false
        inNote = false
        currentText = ""
    }

    /// Build ordered language list: srclang first, then remaining in discovery order
    private func buildLanguageOrder() -> [String] {
        let srcNorm = headerSrclang.lowercased()
        var result: [String] = []

        // Find the srclang entry (case-insensitive match)
        if let srcEntry = languageOrder.first(where: { $0.lowercased() == srcNorm }) {
            result.append(srcEntry)
        }

        for lang in languageOrder where lang.lowercased() != srcNorm {
            result.append(lang)
        }

        return result
    }

    private func addLanguage(_ lang: String) {
        let key = lang.lowercased()
        if !languageSet.contains(key) {
            languageSet.insert(key)
            languageOrder.append(lang)
        }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "header":
            headerSrclang = attributeDict["srclang"] ?? ""

        case "tu":
            inTU = true
            currentTuid = attributeDict["tuid"] ?? ""
            currentTuSrclang = attributeDict["srclang"]
            currentSegments = [:]
            currentNote = nil
            currentTuvNotes = [:]

        case "tuv":
            if inTU {
                inTUV = true
                // xml:lang may appear as "xml:lang" or "lang" depending on namespace processing
                currentLang = attributeDict["xml:lang"] ?? attributeDict["lang"] ?? ""
                addLanguage(currentLang)
            }

        case "seg":
            if inTUV {
                inSeg = true
                currentText = ""
            }

        case "note":
            if inTU {
                inNote = true
                currentText = ""
            }

        default:
            if inSeg && Self.visibleInlineElements.contains(localName) {
                var tagText = "<\(localName)"
                if let id = attributeDict["i"] {
                    tagText += " i=\"\(id)\""
                } else if let id = attributeDict["x"] {
                    tagText += " x=\"\(id)\""
                }
                if let pos = attributeDict["pos"] {
                    tagText += " pos=\"\(pos)\""
                }
                tagText += ">"
                currentText += tagText
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSeg || inNote {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "seg":
            if inSeg {
                currentSegments[currentLang] = currentText
                inSeg = false
            }

        case "tuv":
            inTUV = false

        case "note":
            if inTU && inNote {
                if inTUV {
                    currentTuvNotes[currentLang] = currentText
                } else {
                    currentNote = currentText
                }
                inNote = false
            }

        case "tu":
            let unit = TMXUnit(tuid: currentTuid,
                               srclang: currentTuSrclang,
                               segments: currentSegments,
                               note: currentNote,
                               tuvNotes: currentTuvNotes)
            units.append(unit)
            inTU = false

        default:
            if inSeg && Self.visibleInlineElements.contains(localName) {
                currentText += "</\(localName)>"
            }
        }
    }
}
