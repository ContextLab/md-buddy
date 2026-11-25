import Foundation

/// One piece of math found in Markdown source: the TeX without its delimiters.
struct MathSpan: Equatable {
    let tex: String
    let display: Bool

    /// The math as it can be written back into text: bare environments as they are,
    /// everything else between dollar signs.
    var source: String {
        if tex.hasPrefix("\\begin{") { return tex }
        return display ? "$$\(tex)$$" : "$\(tex)$"
    }
}

/// Finds math in Markdown source and hides it from cmark, which would otherwise read the
/// underscores and asterisks inside `$a_i + b_i$` as emphasis.
///
/// `protect` swaps each math span for a placeholder made of letters and digits, which cmark
/// passes through untouched; `restore` swaps the placeholders in the rendered HTML for
/// `<span class="math math-inline|math-display">` elements holding the escaped TeX, which the
/// page script hands to KaTeX.
///
/// Delimiters: `$…$` and `\(…\)` inline, `$$…$$` and `\[…\]` display. A `$` opens inline math
/// only when the next character is not whitespace, and closes it only when the previous
/// character is not whitespace and the next is not a digit, so "costs $5 and $10" is left
/// alone (the rule GitHub and Pandoc use). `\$` is a literal dollar sign. Math never spans a
/// blank line, inline math never runs into the next list item, and nothing inside code spans
/// or code blocks is math. Math inside a block quote loses the quote markers of its
/// continuation lines. A placeholder that ends up inside a tag (image alt text, an attribute
/// of raw HTML) is put back as plain text, since an element there would break the tag.
enum MathScanner {
    static func protect(_ markdown: String, bareEnvironments: Bool)
        -> (text: String, spans: [MathSpan], token: String) {
        guard markdown.contains("$") || markdown.contains("\\(") || markdown.contains("\\[")
                || (bareEnvironments && markdown.contains("\\begin{")) else {
            return (markdown, [], "")
        }
        var scanner = Scanner(chars: Array(markdown), bareEnvironments: bareEnvironments,
                              token: makeToken(avoiding: markdown))
        scanner.run()
        return (scanner.out, scanner.spans, scanner.token)
    }

    static func restore(_ html: String, spans: [MathSpan], token: String) -> String {
        guard !spans.isEmpty, !token.isEmpty else { return html }
        let parts = html.components(separatedBy: token)
        var out = parts[0]
        var tags = TagTracker()
        tags.advance(over: parts[0])
        for part in parts.dropFirst() {
            let digits = part.prefix { $0.isASCII && $0.isNumber }
            let rest = part.dropFirst(digits.count)
            if let index = Int(digits), index < spans.count, rest.first == "Z" {
                let span = spans[index]
                if tags.insideTag {
                    out += HTML.escape(span.source)
                } else {
                    out += "<span class=\"math \(span.display ? "math-display" : "math-inline")\">"
                    out += HTML.escape(span.tex)
                    out += "</span>"
                }
                out += rest.dropFirst()
                tags.advance(over: rest.dropFirst())
            } else {
                out += token + part
                tags.advance(over: part)
            }
        }
        return out
    }

    /// Follows rendered HTML far enough to say whether the current position is inside a tag
    /// (between `<name` and its closing `>`, quoted attribute values included).
    private struct TagTracker {
        private(set) var insideTag = false
        private var quote: UInt8 = 0
        private var afterOpen = false

        mutating func advance(over text: some StringProtocol) {
            for byte in text.utf8 {
                if insideTag {
                    if quote != 0 {
                        if byte == quote { quote = 0 }
                    } else if byte == 0x22 || byte == 0x27 {
                        quote = byte
                    } else if byte == 0x3E {
                        insideTag = false
                    }
                } else if afterOpen {
                    afterOpen = false
                    // `<` starts a tag only before a letter, `/` or `!`; cmark escapes any other.
                    let letter = (byte | 0x20) >= 0x61 && (byte | 0x20) <= 0x7A
                    if letter || byte == 0x2F || byte == 0x21 { insideTag = true } else if byte == 0x3C { afterOpen = true }
                } else if byte == 0x3C {
                    afterOpen = true
                }
            }
        }
    }

    /// A placeholder prefix that does not occur in the document.
    private static func makeToken(avoiding text: String) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        while true {
            let token = "MDBMATH" + String((0..<10).map { _ in letters.randomElement()! })
            if !text.contains(token) { return token }
        }
    }

    private struct Scanner {
        let chars: [Character]
        let bareEnvironments: Bool
        let token: String
        let code: [Bool]
        var out = ""
        var spans: [MathSpan] = []
        /// Searches that failed: delimiter → the index before which a new search for it must
        /// also fail. A failed search runs to the end of its paragraph, so without this a
        /// paragraph of unclosed openers ("$5 $6 $7 …") would be scanned once per opener.
        var failedBefore: [String: Int] = [:]

        init(chars: [Character], bareEnvironments: Bool, token: String) {
            self.chars = chars
            self.bareEnvironments = bareEnvironments
            self.token = token
            self.code = MathScanner.codeBlockMask(chars)
        }

        mutating func add(_ tex: ArraySlice<Character>, display: Bool) {
            out += token + String(spans.count) + "Z"
            spans.append(MathSpan(tex: withoutQuoteMarkers(tex), display: display))
        }

        /// Math that starts inside a block quote and runs over several lines: the `>` markers
        /// that start its later lines belong to the quote, not to the formula.
        func withoutQuoteMarkers(_ tex: ArraySlice<Character>) -> String {
            guard tex.contains("\n") else { return String(tex) }
            var lineStart = tex.startIndex
            while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
            let depth = quoteMarkers(from: lineStart, limit: tex.startIndex, atMost: .max).count
            guard depth > 0 else { return String(tex) }
            var result = ""
            var j = tex.startIndex
            while j < tex.endIndex {
                result.append(chars[j])
                j += 1
                if chars[j - 1] == "\n" {
                    j = quoteMarkers(from: j, limit: tex.endIndex, atMost: depth).end
                }
            }
            return result
        }

        /// Counts the block-quote markers (`>` with up to three spaces before and one after)
        /// that start at `start`, and where the text after them begins.
        func quoteMarkers(from start: Int, limit: Int, atMost: Int) -> (count: Int, end: Int) {
            var count = 0
            var end = start
            while count < atMost {
                var j = end
                var indent = 0
                while j < limit, chars[j] == " ", indent < 3 {
                    j += 1
                    indent += 1
                }
                guard j < limit, chars[j] == ">" else { break }
                j += 1
                if j < limit, chars[j] == " " { j += 1 }
                end = j
                count += 1
            }
            return (count, end)
        }

        mutating func run() {
            let n = chars.count
            var i = 0
            while i < n {
                let c = chars[i]
                if code[i] {
                    out.append(c)
                    i += 1
                    continue
                }
                switch c {
                case "\\":
                    guard i + 1 < n else {
                        out.append(c)
                        i += 1
                        continue
                    }
                    let next = chars[i + 1]
                    if next == "(" || next == "[" {
                        let close: [Character] = ["\\", next == "(" ? ")" : "]"]
                        if let end = find(close, from: i + 2, inline: next == "("), !isBlank(chars[(i + 2)..<end]) {
                            add(chars[(i + 2)..<end], display: next == "[")
                            i = end + 2
                            continue
                        }
                    } else if bareEnvironments, let open = environmentOpening(at: i) {
                        let close = Array("\\end{\(open.name)}")
                        if let end = find(close, from: i + open.length) {
                            add(chars[i..<(end + close.count)], display: true)
                            i = end + close.count
                            continue
                        }
                    }
                    // A backslash escape (including `\$`): cmark deals with it.
                    out.append(c)
                    out.append(next)
                    i += 2

                case "`":
                    var run = 0
                    while i + run < n, chars[i + run] == "`" { run += 1 }
                    if let end = closingBackticks(count: run, from: i + run) {
                        out += String(chars[i..<end])
                        i = end
                    } else {
                        out += String(chars[i..<(i + run)])
                        i += run
                    }

                case "$":
                    if i + 1 < n, chars[i + 1] == "$" {
                        if let end = find(["$", "$"], from: i + 2), !isBlank(chars[(i + 2)..<end]) {
                            add(chars[(i + 2)..<end], display: true)
                            i = end + 2
                        } else {
                            out += "$$"
                            i += 2
                        }
                    } else if let end = inlineClose(from: i + 1) {
                        add(chars[(i + 1)..<end], display: false)
                        i = end + 1
                    } else {
                        out.append(c)
                        i += 1
                    }

                default:
                    out.append(c)
                    i += 1
                }
            }
        }

        func isBlank(_ slice: ArraySlice<Character>) -> Bool { slice.allSatisfy(\.isWhitespace) }

        /// True when the newline at `index` is followed by a blank line (a paragraph break).
        /// A line holding only block-quote markers is blank too.
        func paragraphEnds(at index: Int) -> Bool {
            var j = index + 1
            while j < chars.count, chars[j] == " " || chars[j] == "\t" || chars[j] == ">" { j += 1 }
            return j >= chars.count || chars[j] == "\n"
        }

        /// True when the line after the newline at `index` starts a list item (looking past
        /// block-quote markers). Inline math stops there: the next item is a new block.
        func listItemStarts(after index: Int) -> Bool {
            var j = index + 1
            while j < chars.count, chars[j] == " " || chars[j] == "\t" || chars[j] == ">" { j += 1 }
            var end = j
            while end < chars.count, end - j < 12, chars[end] != "\n" { end += 1 }
            return MathScanner.isListItem(chars[j..<end])
        }

        /// How far to step over the backslash at `index`: past the character it escapes, but
        /// never past a line end, which has to stay visible to the paragraph check.
        func escapeLength(at index: Int) -> Int {
            index + 1 < chars.count && chars[index + 1] == "\n" ? 1 : 2
        }

        /// The index where `pattern` next occurs, searching from `start` without leaving the
        /// paragraph, entering a code block or stopping inside a backslash escape.
        mutating func find(_ pattern: [Character], from start: Int, inline: Bool = false) -> Int? {
            let key = String(pattern)
            if let limit = failedBefore[key], start < limit { return nil }
            var j = start
            let n = chars.count
            defer { if j > start { failedBefore[key] = j } }
            while j < n {
                if code[j] { return nil }
                if j + pattern.count <= n, chars[j] == pattern[0],
                   Array(chars[j..<(j + pattern.count)]) == pattern {
                    let found = j
                    j = start  // a success is not remembered
                    return found
                }
                if chars[j] == "\\" {
                    j += escapeLength(at: j)
                    continue
                }
                if chars[j] == "\n", paragraphEnds(at: j) || (inline && listItemStarts(after: j)) { return nil }
                j += 1
            }
            return nil
        }

        /// The index of the `$` closing inline math whose content starts at `start`.
        mutating func inlineClose(from start: Int) -> Int? {
            let n = chars.count
            guard start < n, !chars[start].isWhitespace, chars[start] != "$" else { return nil }
            if let limit = failedBefore["$"], start < limit { return nil }
            var j = start
            defer { if j > start { failedBefore["$"] = j } }
            while j < n {
                if code[j] { return nil }
                let c = chars[j]
                if c == "\\" {
                    j += escapeLength(at: j)
                    continue
                }
                if c == "`" {
                    // Code spans bind tighter than math: a span that starts here ends the search.
                    var run = 0
                    while j + run < n, chars[j + run] == "`" { run += 1 }
                    if closingBackticks(count: run, from: j + run) != nil { return nil }
                    j += run
                    continue
                }
                if c == "\n", paragraphEnds(at: j) || listItemStarts(after: j) { return nil }
                if c == "$", j > start, !chars[j - 1].isWhitespace {
                    let followedByDigit = j + 1 < n && chars[j + 1].isASCII && chars[j + 1].isNumber
                    if !followedByDigit {
                        let found = j
                        j = start  // a success is not remembered
                        return found
                    }
                }
                j += 1
            }
            return nil
        }

        /// The index just past the backtick run that closes a code span opened by `count`
        /// backticks, or nil when the span is never closed in this paragraph.
        mutating func closingBackticks(count: Int, from start: Int) -> Int? {
            let key = "`\(count)"
            if let limit = failedBefore[key], start < limit { return nil }
            var j = start
            let n = chars.count
            defer { if j > start { failedBefore[key] = j } }
            while j < n {
                if code[j] { return nil }
                if chars[j] == "\n", paragraphEnds(at: j) { return nil }
                if chars[j] == "`" {
                    var run = 0
                    while j + run < n, chars[j + run] == "`" { run += 1 }
                    if run == count {
                        let found = j + run
                        j = start  // a success is not remembered
                        return found
                    }
                    j += run
                    continue
                }
                j += 1
            }
            return nil
        }

        /// Matches `\begin{name}` at `index`, where name is letters with an optional `*`.
        ///
        /// This is Jupyter's rule for math written without `$` in a Markdown cell. JupyterLab
        /// (packages/rendermime/src/latex.ts, `removeMath`) splits the text on
        ///     /(\$\$?|\\(?:begin|end)\{[a-z]*\*?\}|\\[{}$]|[{}]|(?:\n\s*)+|@@\d+@@|\\\\[()[\]])/i
        /// and on a `\begin{…}` block sets `end = '\\end' + block.substr(6)`, so the math runs
        /// to the `\end` with the same name; a block matching /\n.*\n/ (a blank line) cancels it.
        func environmentOpening(at index: Int) -> (name: String, length: Int)? {
            let prefix = Array("\\begin{")
            guard index + prefix.count < chars.count,
                  Array(chars[index..<(index + prefix.count)]) == prefix else { return nil }
            var j = index + prefix.count
            var name = ""
            while j < chars.count, chars[j].isASCII, chars[j].isLetter {
                name.append(chars[j])
                j += 1
            }
            if j < chars.count, chars[j] == "*" {
                name.append("*")
                j += 1
            }
            guard j < chars.count, chars[j] == "}" else { return nil }
            return (name, j + 1 - index)
        }
    }

    /// Marks every character that belongs to a fenced or indented code block.
    static func codeBlockMask(_ chars: [Character]) -> [Bool] {
        var mask = [Bool](repeating: false, count: chars.count)
        var fence: (char: Character, count: Int)?
        var previousBlank = true
        var inIndented = false
        var inList = false

        var lineStart = 0
        while lineStart < chars.count {
            var lineEnd = lineStart
            while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }
            let next = min(lineEnd + 1, chars.count)
            defer { lineStart = next }

            // Indentation and content, looking through block-quote markers.
            var j = lineStart
            var indent = 0
            func skipIndent() {
                indent = 0
                while j < lineEnd, chars[j] == " " || chars[j] == "\t" {
                    indent += chars[j] == "\t" ? 4 : 1
                    j += 1
                }
            }
            skipIndent()
            while j < lineEnd, chars[j] == ">", indent < 4 {
                j += 1
                if j < lineEnd, chars[j] == " " { j += 1 }
                skipIndent()
            }
            let content = chars[j..<lineEnd]

            func markLine() { for k in lineStart..<next { mask[k] = true } }
            func fenceRun(_ char: Character) -> Int {
                var run = 0
                for c in content {
                    if c == char { run += 1 } else { break }
                }
                return run
            }

            if let open = fence {
                markLine()
                let run = fenceRun(open.char)
                if run >= open.count, content.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil }
                previousBlank = false
                continue
            }
            if content.allSatisfy(\.isWhitespace) {
                previousBlank = true
                continue
            }
            if indent < 4 || inList, let first = content.first, first == "`" || first == "~" {
                let run = fenceRun(first)
                // A backtick fence's info string cannot contain a backtick (that is a code span).
                if run >= 3, first == "~" || !content.dropFirst(run).contains("`") {
                    fence = (first, run)
                    inIndented = false
                    markLine()
                    previousBlank = false
                    continue
                }
            }
            if indent >= 4, !inList, previousBlank || inIndented {
                inIndented = true
                markLine()
                previousBlank = false
                continue
            }
            inIndented = false
            if isListItem(content) {
                inList = true
            } else if indent < 2, previousBlank {
                inList = false
            }
            previousBlank = false
        }
        return mask
    }

    /// `- `, `* `, `+ `, `1. ` or `1) ` at the start of a line's content.
    fileprivate static func isListItem(_ content: ArraySlice<Character>) -> Bool {
        guard let first = content.first else { return false }
        var rest = content.dropFirst()
        if first == "-" || first == "*" || first == "+" {
            return rest.first == " " || rest.first == "\t"
        }
        guard first.isASCII, first.isNumber else { return false }
        while let c = rest.first, c.isASCII, c.isNumber { rest = rest.dropFirst() }
        guard let marker = rest.first, marker == "." || marker == ")" else { return false }
        rest = rest.dropFirst()
        return rest.first == " " || rest.first == "\t"
    }
}
