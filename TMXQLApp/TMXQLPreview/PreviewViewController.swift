import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var document: TMXDocument?
    private var rowHeightCache: [Int: CGFloat] = [:]

    // Measurement cell for height calculation
    private lazy var measureField: NSTextField = {
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.maximumNumberOfLines = 0
        tf.lineBreakMode = .byWordWrapping
        return tf
    }()

    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let parser = TMXParser()
        let doc: TMXDocument

        do {
            doc = try parser.parse(contentsOf: url)
        } catch {
            await MainActor.run {
                showError("Failed to parse TMX: \(error.localizedDescription)")
            }
            return
        }

        await MainActor.run {
            document = doc
            rowHeightCache = [:]
            setupUI(languages: doc.languages)
            tableView.reloadData()
        }
    }

    private func showError(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - UI Setup

    private func setupUI(languages: [String]) {
        scrollView = NSScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.selectionHighlightStyle = .none

        // # column (tuid)
        let idColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tuid"))
        idColumn.title = "#"
        idColumn.width = 80
        idColumn.minWidth = 50
        idColumn.maxWidth = 150
        tableView.addTableColumn(idColumn)

        // One column per language — srclang first
        for lang in languages {
            let colId = NSUserInterfaceItemIdentifier("lang_\(lang)")
            let col = NSTableColumn(identifier: colId)
            col.title = lang
            col.width = 200
            col.minWidth = 100
            tableView.addTableColumn(col)
        }

        // Note column
        let noteColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        noteColumn.title = "Note"
        noteColumn.width = 120
        noteColumn.minWidth = 60
        noteColumn.maxWidth = 300
        tableView.addTableColumn(noteColumn)

        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        view.addSubview(scrollView)
    }

    // MARK: - Height Calculation

    private func cellHeight(for string: String, font: NSFont, columnWidth: CGFloat) -> CGFloat {
        guard !string.isEmpty else { return font.pointSize + 6 }
        measureField.stringValue = string
        measureField.font = font
        guard let cell = measureField.cell else { return 20 }
        let bounds = NSRect(x: 0, y: 0, width: columnWidth, height: .greatestFiniteMagnitude)
        return cell.cellSize(forBounds: bounds).height
    }

    private func columnWidth(_ id: String) -> CGFloat {
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.width ?? 200
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension PreviewViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return document?.units.count ?? 0
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if let cached = rowHeightCache[row] { return cached }

        guard let doc = document else { return 20 }
        let unit = doc.units[row]
        let font = NSFont.systemFont(ofSize: 13)

        var maxH: CGFloat = 20
        for lang in doc.languages {
            var text = unit.segments[lang] ?? "—"
            if let tuvNote = unit.tuvNotes[lang] {
                text += "\n[\(tuvNote)]"
            }
            let h = cellHeight(for: text, font: font, columnWidth: columnWidth("lang_\(lang)"))
            if h > maxH { maxH = h }
        }
        if let note = unit.note {
            let noteH = cellHeight(for: note, font: .systemFont(ofSize: 11), columnWidth: columnWidth("note"))
            if noteH > maxH { maxH = noteH }
        }

        rowHeightCache[row] = maxH
        return maxH
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let doc = document, let columnId = tableColumn?.identifier else { return nil }

        let unit = doc.units[row]

        let cellId = NSUserInterfaceItemIdentifier("Cell_\(columnId.rawValue)")
        let cell: NSTextField

        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(wrappingLabelWithString: "")
            cell.identifier = cellId
            cell.maximumNumberOfLines = 0
            cell.lineBreakMode = .byWordWrapping
            cell.cell?.wraps = true
            cell.cell?.isScrollable = false
            cell.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        switch columnId.rawValue {
        case "tuid":
            cell.stringValue = unit.tuid
            cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textColor = .secondaryLabelColor

        case "note":
            if let note = unit.note {
                cell.stringValue = note
                cell.font = .systemFont(ofSize: 11)
                cell.textColor = .secondaryLabelColor
            } else {
                cell.stringValue = ""
                cell.font = .systemFont(ofSize: 11)
                cell.textColor = .tertiaryLabelColor
            }

        default:
            // Language column: strip "lang_" prefix to get language code
            let lang = String(columnId.rawValue.dropFirst(5))
            let effectiveSrclang = unit.srclang ?? doc.srclang
            let isSrclang = lang.lowercased() == effectiveSrclang.lowercased()

            if let text = unit.segments[lang] {
                var display = text
                if let tuvNote = unit.tuvNotes[lang] {
                    display += "\n[\(tuvNote)]"
                }
                cell.stringValue = display
                cell.font = isSrclang
                    ? .systemFont(ofSize: 13, weight: .semibold)
                    : .systemFont(ofSize: 13)
                cell.textColor = .labelColor
            } else {
                cell.stringValue = "—"
                cell.font = .systemFont(ofSize: 13)
                cell.textColor = .tertiaryLabelColor
            }
        }

        return cell
    }
}
