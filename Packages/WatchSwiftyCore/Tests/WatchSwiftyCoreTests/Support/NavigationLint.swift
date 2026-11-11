import Foundation

/// Finds navigation that makes SwiftUI push and pop in a loop (see `NavigationStyleTests`):
/// - a `NavigationLink` without `value:` (it carries a destination view),
/// - `navigationDestination(isPresented:)` or `navigationDestination(item:)`,
/// - a `NavigationStack` anywhere but a tab root (`MainTabView.swift`), onboarding or a view named `…Sheet`,
/// - a `navigationDestination(for:)` type registered more than once.
/// Comments are skipped, calls may span several lines. A source scanner, not a parser: good enough for this app.
enum NavigationLint {
    struct Source: Sendable {
        /// Path relative to the app folder, e.g. `Account/AccountView.swift`.
        var path: String
        var text: String
    }

    /// One line per problem, starting with `path:line:`.
    static func problems(in sources: [Source]) -> [String] {
        var problems: [String] = []
        var registrations: [(type: String, location: String)] = []

        for source in sources {
            let code = Array(withoutComments(source.text))
            func location(_ index: Int) -> String {
                "\(source.path):\(code[..<index].count { $0 == "\n" } + 1)"
            }

            for index in occurrences(of: "NavigationLink", in: code) {
                let next = skippingSpace(code, from: index + "NavigationLink".count)
                guard next < code.count else { continue }
                let carriesView = switch code[next] {
                case "{": true
                case "(": closingParen(code, open: next).map { !String(code[next...$0]).contains("value:") } ?? false
                default: false
                }
                if carriesView {
                    problems.append("\(location(index)): NavigationLink with a destination view – use NavigationLink(value:)")
                }
            }

            for index in occurrences(of: "navigationDestination", in: code) {
                let open = skippingSpace(code, from: index + "navigationDestination".count)
                guard open < code.count, code[open] == "(", let close = closingParen(code, open: open) else { continue }
                let arguments = String(code[(open + 1)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                if arguments.hasPrefix("for:") {
                    registrations.append((arguments.dropFirst(4).trimmingCharacters(in: .whitespaces), location(index)))
                } else {
                    let label = arguments.prefix { $0 != ":" }
                    problems.append("\(location(index)): navigationDestination(\(label):) – use navigationDestination(for:) with a value link")
                }
            }

            for index in occurrences(of: "NavigationStack", in: code) {
                let owner = enclosingStruct(code, before: index)
                let allowed = source.path.hasSuffix("MainTabView.swift") || source.path.hasPrefix("Onboarding/")
                    || owner?.hasSuffix("Sheet") == true
                if !allowed {
                    problems.append("\(location(index)): NavigationStack in \(owner ?? "?") – only tab roots, onboarding and …Sheet views have their own stack")
                }
            }
        }

        for (type, entries) in Dictionary(grouping: registrations, by: \.type) where entries.count > 1 {
            let places = entries.map(\.location).joined(separator: ", ")
            problems.append("\(entries[1].location): navigationDestination(for: \(type)) registered \(entries.count) times (\(places))")
        }
        return problems
    }

    /// The text with `//` and `/* */` comments removed; line breaks stay, so line numbers do not move.
    static func withoutComments(_ text: String) -> String {
        let chars = Array(text)
        var result: [Character] = []
        var index = 0
        var inString = false
        while index < chars.count {
            let char = chars[index]
            let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            if inString {
                result.append(char)
                if char == "\\", let next {
                    result.append(next)
                    index += 2
                    continue
                }
                if char == "\"" { inString = false }
                index += 1
            } else if char == "/", next == "/" {
                while index < chars.count, chars[index] != "\n" { index += 1 }
            } else if char == "/", next == "*" {
                index += 2
                while index < chars.count, !(chars[index] == "*" && index + 1 < chars.count && chars[index + 1] == "/") {
                    if chars[index] == "\n" { result.append("\n") }
                    index += 1
                }
                index += 2
            } else {
                if char == "\"" { inString = true }
                result.append(char)
                index += 1
            }
        }
        return String(result)
    }

    /// Start indices of `word` where it is not part of a longer identifier.
    private static func occurrences(of word: String, in code: [Character]) -> [Int] {
        let target = Array(word)
        guard code.count >= target.count else { return [] }
        return (0...(code.count - target.count)).filter { start in
            guard Array(code[start..<(start + target.count)]) == target else { return false }
            let before = start > 0 ? code[start - 1] : " "
            let after = start + target.count < code.count ? code[start + target.count] : " "
            return !isIdentifier(before) && !isIdentifier(after)
        }
    }

    private static func isIdentifier(_ char: Character) -> Bool { char.isLetter || char.isNumber || char == "_" }

    private static func skippingSpace(_ code: [Character], from index: Int) -> Int {
        var index = index
        while index < code.count, code[index].isWhitespace { index += 1 }
        return index
    }

    /// Index of the `)` matching the `(` at `open`, skipping parentheses inside string literals.
    private static func closingParen(_ code: [Character], open: Int) -> Int? {
        var depth = 0
        var inString = false
        var index = open
        while index < code.count {
            let char = code[index]
            if inString {
                if char == "\\" {
                    index += 2
                    continue
                }
                if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
            } else if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    /// Name of the last `struct` declared before `index`.
    private static func enclosingStruct(_ code: [Character], before index: Int) -> String? {
        guard let start = occurrences(of: "struct", in: Array(code[..<index])).last else { return nil }
        let name = skippingSpace(code, from: start + "struct".count)
        return String(code[name...].prefix(while: isIdentifier))
    }
}
