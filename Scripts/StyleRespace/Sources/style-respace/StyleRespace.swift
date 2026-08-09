//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import SwiftParser
import SwiftSyntax

// A parser-aware post-pass for the handful of code-style rules swift-format can't express. It re-inserts
// interior spaces on single-line collection *literals* (`[.foo]` → `[ .foo ]`), normalises guard / ternary /
// if-condition layout, blank lines around members and guards, expression `return`s, and member attribute
// breaks — and finally, as two string-level fixpoint passes, drops `;` statement separators onto their own
// lines and collapses the parens of single-argument calls (`foo(\n  .bar { … }\n)` → `foo(.bar { … })`).
// Because it works on the parsed syntax tree, the literal pass touches only ArrayExpr / DictionaryExpr nodes —
// array TYPES (`[Int]`), subscripts (`arr[0]`), strings, and comments are different nodes and are left alone.
@main
struct StyleRespace {
    static func main() throws {
        var paths = Array(CommandLine.arguments.dropFirst())
        let check = paths.contains("--check")
        paths.removeAll { $0.hasPrefix("--") }

        // No paths (or `-`): act as a stdin → stdout filter, so it can be piped after swift-format.
        if paths.isEmpty || paths == [ "-" ] {
            let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
            FileHandle.standardOutput.write(Data(respaced(input).utf8))
            return
        }

        var changed = 0
        for path in paths {
            let url: URL = .init(fileURLWithPath: path)
            guard let original = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let result = respaced(original)
            guard result != original else { continue }

            changed += 1
            if check {
                print("✗ \(path)")
            } else {
                try result.write(to: url, atomically: true, encoding: .utf8)
            }
        }

        if check, changed > 0 { exit(1) }
    }

    private static func respaced(_ source: String) -> String {
        // Drop `;` separators first (a string pass, re-parsing to a fixpoint), BEFORE the rewriters: turning a
        // single-line braced body multi-line can change how it should be laid out (e.g. a guard whose body
        // becomes multi-line must then explode its head), and GuardNormalizer et al. need to see that.
        let tree = Parser.parse(source: explodedSemicolons(source))
        let literals = CollectionLiteralSpacer().rewrite(tree)
        let expressions = ExpressionReturnNormalizer().rewrite(literals)
        let guards = GuardNormalizer().rewrite(expressions)
        let ternaries = TernaryNormalizer().rewrite(guards)
        let blanks = BlankLineNormalizer().rewrite(ternaries)
        let ifs = IfConditionNormalizer().rewrite(blanks)
        let rewritten = MemberAttributeNormalizer().rewrite(ifs).description

        // Collapse the parens of a single-argument call, so a lone argument (e.g. a trailing closure's body)
        // is no longer broken onto its own line. Then collapse any *multi*-argument call whose whole one-line
        // form fits the line limit (swift-format respects the existing breaks and won't). Both run on the
        // laid-out result and never re-introduce a `;`, so the whole pipeline stays a fixpoint.
        let single = unwrappedSingleArgumentCalls(rewritten)
        return collapsedFittingCalls(single)
    }
}

private final class CollectionLiteralSpacer: SyntaxRewriter {
    override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {
        guard !isTypeConstructor(Syntax(node)) else { return super.visit(node) }
        guard let visited = super.visit(node).as(ArrayExprSyntax.self) else { return super.visit(node) }
        guard
            !visited.elements.isEmpty,
            isSingleLine(visited.leftSquare, visited.elements, visited.rightSquare)
        else { return ExprSyntax(visited) }

        var result = visited
        (result.leftSquare, result.rightSquare) = spacedBrackets(
            left: visited.leftSquare,
            firstLeading: visited.elements.first?.leadingTrivia ?? [],
            lastTrailing: visited.elements.last?.trailingTrivia ?? [],
            right: visited.rightSquare
        )
        return ExprSyntax(result)
    }

    override func visit(_ node: DictionaryExprSyntax) -> ExprSyntax {
        guard !isTypeConstructor(Syntax(node)) else { return super.visit(node) }
        guard let visited = super.visit(node).as(DictionaryExprSyntax.self) else { return super.visit(node) }
        guard
            case .elements(let elements) = visited.content,
            !elements.isEmpty,
            isSingleLine(visited.leftSquare, elements, visited.rightSquare)
        else { return ExprSyntax(visited) }

        var result = visited
        (result.leftSquare, result.rightSquare) = spacedBrackets(
            left: visited.leftSquare,
            firstLeading: elements.first?.leadingTrivia ?? [],
            lastTrailing: elements.last?.trailingTrivia ?? [],
            right: visited.rightSquare
        )
        return ExprSyntax(result)
    }

    // Only single-line literals get interior spaces; multi-line literals keep their own layout.
    private func isSingleLine(_ open: TokenSyntax, _ elements: some SyntaxProtocol, _ close: TokenSyntax) -> Bool {
        let interior = open.trailingTrivia.description + elements.description + close.leadingTrivia.description
        return !interior.contains("\n")
    }

    // Adds one interior space on each side, but only when that side has no whitespace yet. The gap after `[`
    // can live in the bracket's trailing trivia or the first element's leading trivia; the gap before `]` in
    // the last element's trailing trivia or the bracket's leading trivia — so both ends are checked. This
    // keeps the tool idempotent and never doubles an existing space.
    private func spacedBrackets(
        left: TokenSyntax,
        firstLeading: Trivia,
        lastTrailing: Trivia,
        right: TokenSyntax
    ) -> (TokenSyntax, TokenSyntax) {
        var left = left
        var right = right
        if !hasSpace(left.trailingTrivia), !hasSpace(firstLeading) {
            left.trailingTrivia = .space + left.trailingTrivia
        }
        if !hasSpace(lastTrailing), !hasSpace(right.leadingTrivia) {
            right.leadingTrivia = right.leadingTrivia + .space
        }
        return (left, right)
    }

    private func hasSpace(_ trivia: Trivia) -> Bool {
        trivia.contains { piece in
            return switch piece {
                case .spaces, .tabs: true
                default: false
            }
        }
    }

    // True when this bracket expression (or a collection literal enclosing it) is the called expression of a
    // function call — i.e. `[UInt8](repeating:…)`, `[Int]()`, `[[UInt8]](…)`, `[String: Int](…)`. There the
    // brackets are a *type*, not a value literal, and must stay tight. Climbs only through collection-literal
    // structure so a real literal in argument or member position (`[1, 2, 3].first`) is unaffected.
    private func isTypeConstructor(_ node: Syntax) -> Bool {
        var expression = node
        while true {
            if let call = expression.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == expression.id {
                return true
            }
            guard
                let parent = expression.parent,
                parent.is(ArrayExprSyntax.self) || parent.is(ArrayElementSyntax.self)
                    || parent.is(ArrayElementListSyntax.self) || parent.is(DictionaryExprSyntax.self)
                    || parent.is(DictionaryElementSyntax.self) || parent.is(DictionaryElementListSyntax.self)
            else { return false }

            expression = parent
        }
    }
}

// Normalises `guard` layout to the code style: a guard that fits in `lineLength` collapses to one line
// (`guard a, b else { … }`); otherwise it explodes — `guard` alone on its line, one condition per indented
// line, `else` on its own line — keeping swift-format's already-correct `else`/body. swift-format can't do
// this (it breaks by length, not per-condition), and the SwiftLint regex rule can only flag it, not fix it.
private final class GuardNormalizer: SyntaxRewriter {
    private let lineLength = 120

    override func visit(_ node: GuardStmtSyntax) -> StmtSyntax {
        let rewritten = super.visit(node)
        guard let node = rewritten.as(GuardStmtSyntax.self) else { return rewritten }

        // Bail only on things we can't restructure safely: a comment in a position that would be destroyed
        // (a condition's own leading line, or before `else`), or a single condition that is itself
        // multi-line. Trailing line comments on a condition are preserved (see `relaid`).
        let conditionTexts = node.conditions.map { $0.condition.trimmedDescription }
        guard
            !node.conditions.isEmpty,
            !hasLeadingComment(node),
            conditionTexts.allSatisfy({ !$0.contains("\n") })
        else { return StmtSyntax(node) }

        let indent = leadingIndentation(node)
        let bodyText = node.body.trimmedDescription

        // A trailing line comment can't share a one-line guard (it would swallow the rest), so only collapse
        // when there are no condition comments at all.
        if !bodyText.contains("\n"), !hasTrailingComment(node) {
            let oneLine = indent + "guard " + conditionTexts.joined(separator: ", ") + " else " + bodyText
            if oneLine.count <= lineLength { return StmtSyntax(relaid(node, indent: indent, multiline: false)) }
        }

        return StmtSyntax(relaid(node, indent: indent, multiline: true))
    }

    // Rebuilds the guard keyword + condition list (and the `else` keyword's leading break) for either layout.
    // The `else` keyword's trailing trivia and the body node are left exactly as swift-format produced them.
    private func relaid(_ node: GuardStmtSyntax, indent: String, multiline: Bool) -> GuardStmtSyntax {
        var node = node
        let elementLeading: Trivia = multiline ? .newline + .spaces(indent.count + 4) : []
        let commaTrailing: Trivia = multiline ? [] : .space

        var elements: [ConditionElementSyntax] = []
        for element in node.conditions {
            var element = element
            // Preserve a trailing line/block comment (it lives on the condition or its comma) — trimming
            // would otherwise drop it.
            let comment =
                commentPieces(element.condition.trailingTrivia)
                + commentPieces(element.trailingComma?.trailingTrivia ?? [])
            element.condition = element.condition.trimmed
            element.leadingTrivia = elementLeading
            if element.trailingComma != nil {
                let trailing: Trivia = comment.isEmpty ? commaTrailing : Trivia(pieces: [ .spaces(2) ] + comment)
                element.trailingComma = .commaToken(trailingTrivia: trailing)
            } else if !comment.isEmpty {
                element.condition = element.condition.with(\.trailingTrivia, Trivia(pieces: [ .spaces(2) ] + comment))
            }
            elements.append(element)
        }

        node.guardKeyword.trailingTrivia = multiline ? [] : .space
        node.conditions = ConditionElementListSyntax(elements)
        node.elseKeyword.leadingTrivia = multiline ? .newline + .spaces(indent.count) : .space
        return node
    }

    // The horizontal whitespace at the start of the guard's own line (assumes space indentation).
    private func leadingIndentation(_ node: some SyntaxProtocol) -> String {
        var indent = ""
        for piece in node.leadingTrivia.reversed() {
            switch piece {
                case .spaces(let count): indent = String(repeating: " ", count: count) + indent
                case .tabs(let count): indent = String(repeating: "\t", count: count) + indent
                default: return indent
            }
        }
        return indent
    }

    // A comment we would destroy by re-laying the conditions: on a condition's own leading line, or in the
    // gap before `else`. (Trailing comments are preserved, so they don't count here.)
    private func hasLeadingComment(_ node: GuardStmtSyntax) -> Bool {
        node.conditions.contains { $0.leadingTrivia.contains(where: { isComment($0) }) }
            || node.elseKeyword.leadingTrivia.contains(where: { isComment($0) })
    }

    private func hasTrailingComment(_ node: GuardStmtSyntax) -> Bool {
        node.conditions.contains { element in
            !commentPieces(element.condition.trailingTrivia).isEmpty
                || !commentPieces(element.trailingComma?.trailingTrivia ?? []).isEmpty
        }
    }

    private func commentPieces(_ trivia: Trivia) -> [TriviaPiece] {
        trivia.filter { isComment($0) }
    }

    private func isComment(_ piece: TriviaPiece) -> Bool {
        return switch piece {
            case .lineComment, .blockComment, .docLineComment, .docBlockComment: true
            default: false
        }
    }
}

// On a multi-line ternary (`?` / `:` each on their own line), keeps the condition on the line it starts —
// swift-format breaks after the `=`/`return` and drops the condition onto its own line; this pulls it back
// up so the layout reads `let x = cond` / `?` / `:` with the operators indented under it. swift-format
// already indents the `?` and `:`; only the leading break before the condition is removed.
//
// `Parser.parse` leaves operators unfolded, so a ternary is a SequenceExpr whose middle element is an
// UnresolvedTernaryExpr (the `? then :`) — not a folded TernaryExpr. We work on that shape.
private final class TernaryNormalizer: SyntaxRewriter {
    override func visit(_ node: SequenceExprSyntax) -> ExprSyntax {
        let rewritten = super.visit(node)
        guard let node = rewritten.as(SequenceExprSyntax.self) else { return rewritten }

        let elements = Array(node.elements)
        guard
            let ternaryIndex = elements.firstIndex(where: { $0.is(UnresolvedTernaryExprSyntax.self) }),
            let ternary = elements[ternaryIndex].as(UnresolvedTernaryExprSyntax.self),
            containsNewline(ternary.questionMark.leadingTrivia) || containsNewline(ternary.colon.leadingTrivia)
        else { return ExprSyntax(node) }

        // Pull up the ternary's condition — the element immediately before the `?` — not elements[0], which
        // in an assignment expression (`self.x = cond ? …`) is the left-hand side. Removing its leading break
        // would swallow a statement separator.
        let conditionIndex = ternaryIndex - 1
        guard
            conditionIndex >= 0,
            containsNewline(elements[conditionIndex].leadingTrivia)
        else {
            return ExprSyntax(node)
        }

        // Only safe when the break is a continuation of an RHS: the whole sequence is a `let x = …` /
        // `return …` value (condition is the first element), or an assignment `=` sits right before it.
        let safe =
            conditionIndex == 0
            ? node.parent?.is(InitializerClauseSyntax.self) == true || node.parent?.is(ReturnStmtSyntax.self) == true
            : elements[conditionIndex - 1].is(AssignmentExprSyntax.self)
        guard safe else { return ExprSyntax(node) }

        var newElements = elements
        newElements[conditionIndex].leadingTrivia = .space
        var result = node
        result.elements = ExprListSyntax(newElements)
        return ExprSyntax(result)
    }

    private func containsNewline(_ trivia: Trivia) -> Bool {
        trivia.contains { piece in
            return switch piece {
                case .newlines, .carriageReturns, .carriageReturnLineFeeds: true
                default: false
            }
        }
    }
}

// Enforces two blank-line rules inside braced bodies / closures (not top level), neither of which
// swift-format can express:
//   • a nested (local) function is surrounded by a blank line;
//   • a `guard` is followed by a blank line, but a run of consecutive guards stays together with the single
//     blank line only after the last one.
// It only adjusts the blank count on a statement that already begins its own line, and preserves any
// comments and indentation in the leading trivia.
private final class BlankLineNormalizer: SyntaxRewriter {
    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        let node = super.visit(node)

        guard node.parent?.is(SourceFileSyntax.self) != true else { return node }

        var items = Array(node)
        guard items.count > 1 else { return node }

        for index in 1 ..< items.count {
            let previous = items[index - 1].item
            let current = items[index].item
            let previousGuard = previous.is(GuardStmtSyntax.self)
            let currentGuard = current.is(GuardStmtSyntax.self)

            var blanks: Int?
            if previousGuard { blanks = currentGuard ? 0 : 1 }
            if current.is(FunctionDeclSyntax.self) || previous.is(FunctionDeclSyntax.self) { blanks = 1 }

            if let blanks { items[index] = withLeadingBlanks(items[index], blanks) }
        }

        return CodeBlockItemListSyntax(items)
    }

    // A type's members: surround each function-like member (method / init / deinit / subscript) with a blank
    // line — swift-format never adds blank lines between members. Adjacent properties stay grouped.
    override func visit(_ node: MemberBlockItemListSyntax) -> MemberBlockItemListSyntax {
        let node = super.visit(node)

        var items = Array(node)
        guard items.count > 1 else { return node }

        for index in 1 ..< items.count where isMethodLike(items[index - 1].decl) || isMethodLike(items[index].decl) {
            items[index] = withLeadingBlanks(items[index], 1)
        }

        return MemberBlockItemListSyntax(items)
    }

    private func isMethodLike(_ decl: DeclSyntax) -> Bool {
        decl.is(FunctionDeclSyntax.self) || decl.is(InitializerDeclSyntax.self)
            || decl.is(DeinitializerDeclSyntax.self) || decl.is(SubscriptDeclSyntax.self)
    }

    private func withLeadingBlanks<Item: SyntaxProtocol>(_ item: Item, _ blanks: Int) -> Item {
        let pieces = Array(item.leadingTrivia)
        var newlineRun = 0
        while newlineRun < pieces.count, isNewline(pieces[newlineRun]) { newlineRun += 1 }

        guard newlineRun > 0 else { return item }

        return item.with(\.leadingTrivia, Trivia(pieces: [ .newlines(blanks + 1) ] + pieces[newlineRun...]))
    }

    private func isNewline(_ piece: TriviaPiece) -> Bool {
        return switch piece {
            case .newlines, .carriageReturns, .carriageReturnLineFeeds: true
            default: false
        }
    }
}

// Turns a statement-form `switch` / `if` whose every branch is a single `return <expr>` into the
// expression form `return switch … { case …: <expr> }` (codestyle: prefer expression `if`/`switch`).
// Only fires when every branch is exactly one `return` with a value; `if` must be exhaustive (have a final
// `else`). swift-format can't do this and a SwiftLint regex can't tell whether every branch returns.
private final class ExpressionReturnNormalizer: SyntaxRewriter {
    override func visit(_ node: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
        let node = super.visit(node)

        // A statement-position `switch` / `if` is an ExpressionStmt wrapping the expression.
        guard
            case .stmt(let statement) = node.item,
            let expr = statement.as(ExpressionStmtSyntax.self)?.expression
        else { return node }

        let converted: ExprSyntax?
        if let switchExpr = expr.as(SwitchExprSyntax.self) {
            converted = expressionSwitch(switchExpr).map(ExprSyntax.init)
        } else if let ifExpr = expr.as(IfExprSyntax.self) {
            converted = expressionIf(ifExpr).map(ExprSyntax.init)
        } else {
            converted = nil
        }

        guard let body = converted else { return node }

        var returnKeyword: TokenSyntax = .keyword(.return)
        returnKeyword.leadingTrivia = expr.leadingTrivia
        returnKeyword.trailingTrivia = .space
        let returnStmt = ReturnStmtSyntax(returnKeyword: returnKeyword, expression: body.with(\.leadingTrivia, []))

        var result = node
        result.item = .stmt(StmtSyntax(returnStmt))
        return result
    }

    private func expressionSwitch(_ node: SwitchExprSyntax) -> SwitchExprSyntax? {
        guard !node.cases.isEmpty else { return nil }

        var cases: [SwitchCaseListSyntax.Element] = []
        for element in node.cases {
            guard
                let switchCase = element.as(SwitchCaseSyntax.self),
                let value = singleReturnedValue(switchCase.statements)
            else { return nil }

            cases.append(.init(switchCase.with(\.statements, asExpression(value))))
        }
        return node.with(\.cases, SwitchCaseListSyntax(cases))
    }

    private func expressionIf(_ node: IfExprSyntax) -> IfExprSyntax? {
        guard
            let thenValue = singleReturnedValue(node.body.statements),
            let elseBody = node.elseBody
        else { return nil }

        let newElse: IfExprSyntax.ElseBody
        switch elseBody {
            case .codeBlock(let block):
                guard let value = singleReturnedValue(block.statements) else { return nil }

                newElse = .codeBlock(block.with(\.statements, asExpression(value)))
            case .ifExpr(let elseIf):
                guard let converted = expressionIf(elseIf) else { return nil }

                newElse = .ifExpr(converted)
        }

        return
            node
            .with(\.body, node.body.with(\.statements, asExpression(thenValue)))
            .with(\.elseBody, newElse)
    }

    // The single `return <expr>`'s value, carrying the `return` keyword's leading trivia (its indentation).
    private func singleReturnedValue(_ statements: CodeBlockItemListSyntax) -> ExprSyntax? {
        guard
            statements.count == 1,
            let only = statements.first,
            let returnStmt = only.item.as(ReturnStmtSyntax.self),
            let value = returnStmt.expression
        else { return nil }

        return value.with(\.leadingTrivia, returnStmt.returnKeyword.leadingTrivia)
    }

    private func asExpression(_ value: ExprSyntax) -> CodeBlockItemListSyntax {
        CodeBlockItemListSyntax([ CodeBlockItemSyntax(item: .expr(value)) ])
    }
}

// Puts the attributes / property wrappers of a *member* property on their own line, above the declaration
// (`@ObservationIgnored let x` → `@ObservationIgnored` ⏎ `let x`). swift-format keeps them inline and has no
// option otherwise. Multiple attributes stay as swift-format laid them out (one line, or wrapped if long);
// only the break between the attribute list and the `let`/`var` (or its access modifier) is inserted. Local
// variables inside function/closure bodies keep their attributes inline, per the code style.
private final class MemberAttributeNormalizer: SyntaxRewriter {
    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        let isMember = node.parent?.is(MemberBlockItemSyntax.self) == true
        guard let node = super.visit(node).as(VariableDeclSyntax.self) else { return super.visit(node) }
        guard isMember, let lastAttribute = node.attributes.last else { return DeclSyntax(node) }

        let indent = leadingIndentation(node)
        let breakTrivia: Trivia = .newline + .spaces(indent.count)

        // Skip if the break is already there (idempotent).
        guard !lastAttribute.trailingTrivia.contains(where: \.isNewline) else { return DeclSyntax(node) }

        var result = node
        result.attributes = node.attributes.with(\.trailingTrivia, breakTrivia)
        if result.modifiers.isEmpty {
            result.bindingSpecifier.leadingTrivia = []
        } else {
            result.modifiers = result.modifiers.with(\.leadingTrivia, [])
        }
        return DeclSyntax(result)
    }

    private func leadingIndentation(_ node: some SyntaxProtocol) -> String {
        var indent = ""
        for piece in node.leadingTrivia.reversed() {
            switch piece {
                case .spaces(let count): indent = String(repeating: " ", count: count) + indent
                case .tabs(let count): indent = String(repeating: "\t", count: count) + indent
                default: return indent
            }
        }
        return indent
    }
}

// Lays out a multi-line `if` statement's wrapped conditions the project way: continuation conditions are
// double-indented (two levels below the `if` line) and the opening `{` stays at the end of the last
// condition line — instead of swift-format's single-indent + brace on its own line. Only standalone,
// line-starting `if` statements with already-wrapped conditions are touched (not `else if`, not the
// `return if` expression form, not single-line ifs).
private final class IfConditionNormalizer: SyntaxRewriter {
    // `if` (including `else if`, reached by recursion, and the `return if` / `let x = if` expression forms):
    // when the condition wrapped — the tell is swift-format putting the body's `{` on its own line — push
    // the continuation lines one indent deeper and bring the `{` up onto the last condition line.
    override func visit(_ node: IfExprSyntax) -> ExprSyntax {
        let rewritten = super.visit(node)
        guard let node = rewritten.as(IfExprSyntax.self) else { return rewritten }
        guard let (conditions, body) = relaid(node.conditions, node.body) else { return ExprSyntax(node) }

        return ExprSyntax(node.with(\.conditions, conditions).with(\.body, body))
    }

    override func visit(_ node: WhileStmtSyntax) -> StmtSyntax {
        let rewritten = super.visit(node)
        guard let node = rewritten.as(WhileStmtSyntax.self) else { return rewritten }
        guard let (conditions, body) = relaid(node.conditions, node.body) else { return StmtSyntax(node) }

        return StmtSyntax(node.with(\.conditions, conditions).with(\.body, body))
    }

    // `repeat { … } while <condition>` has no brace after the condition, so only the continuation indent
    // applies when the trailing condition wraps. `repeat` is always line-starting, so we can bump the
    // single-indented continuation to an absolute double indent (idempotent — there is no brace move to gate
    // re-application as there is for if / while).
    override func visit(_ node: RepeatStmtSyntax) -> StmtSyntax {
        let rewritten = super.visit(node)
        guard let node = rewritten.as(RepeatStmtSyntax.self) else { return rewritten }

        let base = indentWidth(node.leadingTrivia)
        guard
            node.condition.description.contains("\n"),
            let indented = LineReindenter(from: base + 4, to: base + 8)
                .rewrite(node.condition).as(ExprSyntax.self)
        else { return StmtSyntax(node) }

        return StmtSyntax(node.with(\.condition, indented))
    }

    private func indentWidth(_ trivia: Trivia) -> Int {
        var width = 0
        for piece in trivia.reversed() {
            switch piece {
                case .spaces(let count): width += count
                case .tabs(let count): width += count
                default: return width
            }
        }
        return width
    }

    // Double-indents the wrapped condition lines and moves `{` onto the last one. Returns nil (no change)
    // when the conditions are single-line — swift-format keeps `{` inline then.
    private func relaid(
        _ conditions: ConditionElementListSyntax,
        _ body: CodeBlockSyntax
    ) -> (ConditionElementListSyntax, CodeBlockSyntax)? {
        guard
            body.leftBrace.leadingTrivia.contains(where: \.isNewline),
            let indented = ContinuationIndenter(extraSpaces: 4)
                .rewrite(conditions).as(ConditionElementListSyntax.self)
        else { return nil }

        var elements = Array(indented)
        if !elements.isEmpty {
            // Clear the last condition's trailing trivia so the single space comes only from the brace below
            // (keeps the tool idempotent across re-parses).
            elements[elements.count - 1] = elements[elements.count - 1].with(\.trailingTrivia, [])
        }

        var body = body
        body.leftBrace.leadingTrivia = .space
        return (ConditionElementListSyntax(elements), body)
    }
}

// Re-indents every continuation line that sits at exactly `from` spaces to `to` spaces (lines a token starts,
// after a newline in its leading trivia). Idempotent — a line already at `to` is left alone.
private final class LineReindenter: SyntaxRewriter {
    private let from: Int
    private let to: Int

    init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }

    override func visit(_ token: TokenSyntax) -> TokenSyntax {
        guard token.leadingTrivia.contains(where: \.isNewline) else { return token }

        var pieces: [TriviaPiece] = []
        var afterNewline = false
        for piece in token.leadingTrivia {
            switch piece {
                case .newlines, .carriageReturns, .carriageReturnLineFeeds:
                    pieces.append(piece)
                    afterNewline = true
                case .spaces(let count) where afterNewline && count == from:
                    pieces.append(.spaces(to))
                    afterNewline = false
                default:
                    pieces.append(piece)
                    afterNewline = false
            }
        }
        return token.with(\.leadingTrivia, Trivia(pieces: pieces))
    }
}

// Adds `extraSpaces` to the indentation of every line a token starts (the spaces in its leading trivia right
// after a newline), shifting a wrapped construct one indent level deeper without touching single-line trivia.
private final class ContinuationIndenter: SyntaxRewriter {
    private let extraSpaces: Int

    init(extraSpaces: Int) {
        self.extraSpaces = extraSpaces
    }

    override func visit(_ token: TokenSyntax) -> TokenSyntax {
        guard token.leadingTrivia.contains(where: \.isNewline) else { return token }

        var pieces: [TriviaPiece] = []
        var afterNewline = false
        for piece in token.leadingTrivia {
            switch piece {
                case .newlines, .carriageReturns, .carriageReturnLineFeeds:
                    pieces.append(piece)
                    afterNewline = true
                case .spaces(let count) where afterNewline:
                    pieces.append(.spaces(count + extraSpaces))
                    afterNewline = false
                default:
                    if afterNewline { pieces.append(.spaces(extraSpaces)) }
                    pieces.append(piece)
                    afterNewline = false
            }
        }
        return token.with(\.leadingTrivia, Trivia(pieces: pieces))
    }
}

extension TriviaPiece {
    fileprivate var isNewline: Bool {
        return switch self {
            case .newlines, .carriageReturns, .carriageReturnLineFeeds: true
            default: false
        }
    }

    fileprivate var isComment: Bool {
        return switch self {
            case .lineComment, .blockComment, .docLineComment, .docBlockComment: true
            default: false
        }
    }
}

// MARK: - Statement-separator and single-argument-call normalisation
//
// These two passes work on the source *string* (re-parsing to a fixpoint after each edit) rather than as
// SyntaxRewriters. swift-format keeps `;`-separated statements on one line when `respectsExistingLineBreaks`
// lets it, and `lineBreakBeforeEachArgument` breaks even a lone argument onto its own line — neither matches
// the code style. Re-parsing per edit keeps every byte position accurate and means an indentation shift never
// has to be composed across nested edits.

private let lineLength = 120

// Splices `replacement` over the half-open UTF-8 byte range of `source` (SwiftSyntax positions are UTF-8
// offsets, so byte arrays line up exactly with the tree).
private func splice(_ source: String, _ range: Range<Int>, with replacement: String) -> String {
    var bytes = Array(source.utf8)
    bytes.replaceSubrange(range, with: Array(replacement.utf8))
    return String(decoding: bytes, as: UTF8.self)
}

// The number of leading spaces on the physical line that contains `offset` — i.e. the line's indentation,
// regardless of where on the line `offset` falls.
private func lineIndentation(at offset: Int, in bytes: [UInt8]) -> Int {
    var start = min(offset, bytes.count)
    while start > 0, bytes[start - 1] != 0x0A { start -= 1 }

    var indent = 0
    while start + indent < bytes.count, bytes[start + indent] == 0x20 { indent += 1 }
    return indent
}

// MARK: Semicolons

// Drops every `;` statement separator. A single-line braced body (`{ a; b }`) is reflowed to one statement
// per line at the body indent; a `;` anywhere else either splits to a new line (another statement follows on
// the same line) or is simply removed (it already ends its line).
private func explodedSemicolons(_ source: String) -> String {
    var source = source
    while true {
        let tree = Parser.parse(source: source)
        guard
            let semicolon = tree.tokens(viewMode: .sourceAccurate).first(where: { $0.tokenKind == .semicolon })
        else { return source }

        let bytes = Array(source.utf8)
        if let body = enclosingBracedBody(of: semicolon), isSingleLine(body, in: bytes) {
            source = reflowedBody(body, in: source, bytes: bytes)
        } else {
            source = splitOrDropSemicolon(semicolon, in: source, bytes: bytes)
        }
    }
}

// The nearest closure / code-block braces enclosing `token`, with the statement list between them.
private func enclosingBracedBody(
    of token: TokenSyntax
) -> (left: TokenSyntax, statements: CodeBlockItemListSyntax, right: TokenSyntax)? {
    var node: Syntax? = token.parent
    while let current = node {
        if let closure = current.as(ClosureExprSyntax.self) {
            return (closure.leftBrace, closure.statements, closure.rightBrace)
        }
        if let block = current.as(CodeBlockSyntax.self) {
            return (block.leftBrace, block.statements, block.rightBrace)
        }
        node = current.parent
    }
    return nil
}

private func isSingleLine(
    _ body: (left: TokenSyntax, statements: CodeBlockItemListSyntax, right: TokenSyntax),
    in bytes: [UInt8]
) -> Bool {
    let interior = body.left.endPosition.utf8Offset ..< body.right.position.utf8Offset
    return !bytes[interior].contains(0x0A)
}

// Reflows a single-line braced body to one statement per line at `bodyIndent`, the brace line's indent + 4.
// The closing brace drops to the brace line's own indent. A closure signature (`{ x in … }`) stays put — only
// the statements (and the closing brace) move, since they begin after the signature.
private func reflowedBody(
    _ body: (left: TokenSyntax, statements: CodeBlockItemListSyntax, right: TokenSyntax),
    in source: String,
    bytes: [UInt8]
) -> String {
    let braceIndent = lineIndentation(at: body.left.positionAfterSkippingLeadingTrivia.utf8Offset, in: bytes)
    let bodyPad = String(repeating: " ", count: braceIndent + 4)
    let closePad = String(repeating: " ", count: braceIndent)

    let statements = body.statements.map { statementText($0) }.joined(separator: "\n" + bodyPad)
    let replacement = "\n" + bodyPad + statements + "\n" + closePad

    // Back over the horizontal gap after `{` (or after a `… in` signature) so it doesn't survive as a
    // trailing space on the brace line; that whitespace stops at the `{`/`in` token, never crossing it.
    var start = body.statements.position.utf8Offset
    while start > 0, bytes[start - 1] == 0x20 || bytes[start - 1] == 0x09 { start -= 1 }

    let range = start ..< body.right.position.utf8Offset
    return splice(source, range, with: replacement)
}

// The statement's own text, without any trailing `;` (which is a sibling of the statement inside the item).
private func statementText(_ item: CodeBlockItemSyntax) -> String {
    return switch item.item {
        case .decl(let decl): decl.trimmedDescription
        case .stmt(let statement): statement.trimmedDescription
        case .expr(let expression): expression.trimmedDescription
    }
}

// A `;` outside a single-line braced body: insert a line break before the next statement when one follows on
// the same line, otherwise just delete the separator.
private func splitOrDropSemicolon(_ semicolon: TokenSyntax, in source: String, bytes: [UInt8]) -> String {
    let semicolonStart = semicolon.positionAfterSkippingLeadingTrivia.utf8Offset
    let afterSemicolon = semicolon.endPositionBeforeTrailingTrivia.utf8Offset

    var next = afterSemicolon
    while next < bytes.count, bytes[next] == 0x20 || bytes[next] == 0x09 { next += 1 }

    let followedBySameLineStatement = next < bytes.count && bytes[next] != 0x0A
    guard followedBySameLineStatement else { return splice(source, semicolonStart ..< afterSemicolon, with: "") }

    let indent = String(repeating: " ", count: lineIndentation(at: semicolonStart, in: bytes))
    return splice(source, semicolonStart ..< next, with: "\n" + indent)
}

// MARK: Single-argument calls

// Collapses the wrapped parentheses of every single-argument call so the lone argument is no longer broken
// onto its own line — `foo(\n    .bar { … }\n)` becomes `foo(.bar { … })`, with the argument's continuation
// lines pulled back one indent level. Only fires when the collapsed head line still fits in `lineLength`, so a
// genuinely too-long argument keeps its own line — and only when the argument's structure is entirely nested
// (see `argumentIsSmashable`); a wrapped operator / member-access chain or string literal stays exploded.
private func unwrappedSingleArgumentCalls(_ source: String) -> String {
    var source = source
    while true {
        let tree = Parser.parse(source: source)
        let bytes = Array(source.utf8)
        let converter = SourceLocationConverter(fileName: "", tree: tree)

        let collector = CallCollector(viewMode: .sourceAccurate)
        collector.walk(tree)

        guard
            let plan = collector.calls.lazy
                .compactMap({ collapsePlan($0, bytes: bytes, converter: converter) })
                .first
        else { return source }

        source = splice(source, plan.range, with: plan.text)
    }
}

private final class CallCollector: SyntaxVisitor {
    var calls: [FunctionCallExprSyntax] = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        calls.append(node)
        return .visitChildren
    }
}

// The byte range to replace and its replacement text, when `call` is a collapsible single-argument call;
// nil when it isn't one (multiple/zero arguments, a trailing closure, not actually wrapped, or the collapsed
// head line would exceed the limit).
private func collapsePlan(
    _ call: FunctionCallExprSyntax,
    bytes: [UInt8],
    converter: SourceLocationConverter
) -> (range: Range<Int>, text: String)? {
    guard
        let leftParen = call.leftParen,
        let rightParen = call.rightParen,
        call.trailingClosure == nil,
        call.additionalTrailingClosures.isEmpty,
        call.arguments.count == 1,
        let argument = call.arguments.first,
        argument.trailingComma == nil
    else { return nil }

    let calledText = call.calledExpression.trimmedDescription
    guard !calledText.contains("\n") else { return nil }

    // Wrapped means the argument sits on its own line(s): a break after `(` and a break before `)`.
    let argumentStart = call.arguments.positionAfterSkippingLeadingTrivia.utf8Offset
    let argumentEnd = call.arguments.endPositionBeforeTrailingTrivia.utf8Offset
    let openWrapped = bytes[leftParen.endPositionBeforeTrailingTrivia.utf8Offset ..< argumentStart].contains(0x0A)
    let closeWrapped = bytes[argumentEnd ..< rightParen.positionAfterSkippingLeadingTrivia.utf8Offset].contains(0x0A)
    guard openWrapped, closeWrapped else { return nil }
    // A multi-line argument is only smashed onto the head line when its breaks are a *hanging* trailing
    // closure. Anything else — a wrapped member-access / operator chain, a multi-line string literal, or a
    // chain that ends in a multi-line closure — stays exploded (`(` and `)` on their own lines), per the
    // code style.
    guard argumentIsSmashable(argument, start: argumentStart, end: argumentEnd, bytes: bytes) else { return nil }

    // Pulling the argument up onto the call line removes one indent level (its line indent minus the call
    // line's indent) from every continuation line of the argument.
    let argumentIndent = lineIndentation(at: argumentStart, in: bytes)
    let callIndent = lineIndentation(at: rightParen.positionAfterSkippingLeadingTrivia.utf8Offset, in: bytes)
    let dedent = max(0, argumentIndent - callIndent)
    let newCall = calledText + "(" + dedentingContinuationLines(call.arguments.trimmedDescription, by: dedent) + ")"

    // The collapsed head line is whatever already precedes the call on its line (`try await `, an `=`, …)
    // plus everything up to the first line break in the rebuilt call.
    let startColumn = converter.location(for: call.positionAfterSkippingLeadingTrivia).column
    let headWidth = (startColumn - 1) + newCall.prefix { $0 != "\n" }.count
    guard headWidth <= lineLength else { return nil }

    let range = call.positionAfterSkippingLeadingTrivia.utf8Offset ..< call.endPositionBeforeTrailingTrivia.utf8Offset
    return (range, newCall)
}

// True when the lone argument is safe to smash onto the head line. A single-line argument always is (the
// head-width check then governs collapsing). A multi-line argument is safe only when all of its structure is
// *nested* — every line break sits inside a paren / brace / bracket, AND the argument's last physical line
// holds nothing but closing delimiters (`}`, `)`, `]`), commas, and whitespace. So a nested multi-argument
// call (`ServiceGroup(configuration: .init(\n services: …,\n logger: …\n))`) or a hanging trailing closure
// (`send(.conversationMessage(.with { … }))`) collapses, but two things force the call to stay exploded —
// `(` and `)` on their own lines:
//   • a line break at the argument's top level (outside every paren/brace/bracket) — a wrapped member-access
//     or operator chain (`a\n.b\n.c`), or a multi-line string literal (whose breaks belong to no bracket);
//   • a non-delimiter character on the last line — a chain that resumes on the closing brace's own line
//     (`…filter { … }.map(…) ?? []`), which swift-format keeps at top level without a leading break.
private func argumentIsSmashable(
    _ argument: some SyntaxProtocol,
    start: Int,
    end: Int,
    bytes: [UInt8]
) -> Bool {
    guard bytes[start ..< end].contains(0x0A) else { return true }

    let nested = NestedRegionCollector(viewMode: .sourceAccurate)
    nested.walk(argument)
    for offset in start ..< end where bytes[offset] == 0x0A {
        if !nested.regions.contains(where: { $0.contains(offset) }) { return false }
    }

    var lastLineStart = end
    while lastLineStart > start, bytes[lastLineStart - 1] != 0x0A { lastLineStart -= 1 }

    for offset in lastLineStart ..< end {
        switch bytes[offset] {
            case 0x20, 0x09, 0x7D, 0x29, 0x5D, 0x2C: continue  // space, tab, `}`, `)`, `]`, `,`
            default: return false
        }
    }
    return true
}

// The UTF-8 byte range interior to each bracketed construct — call/tuple parens, closure braces, array /
// dictionary / subscript brackets. Used to tell a top-level line break (a wrapped chain or operator sequence)
// from one nested inside a delimiter pair. Multi-line *string* literals are deliberately not recorded, so
// their internal breaks read as top-level and keep the call exploded.
private final class NestedRegionCollector: SyntaxVisitor {
    var regions: [Range<Int>] = []

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.leftBrace, node.rightBrace)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let leftParen = node.leftParen, let rightParen = node.rightParen { record(leftParen, rightParen) }
        return .visitChildren
    }

    override func visit(_ node: TupleExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.leftParen, node.rightParen)
        return .visitChildren
    }

    override func visit(_ node: ArrayExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.leftSquare, node.rightSquare)
        return .visitChildren
    }

    override func visit(_ node: DictionaryExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.leftSquare, node.rightSquare)
        return .visitChildren
    }

    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.leftSquare, node.rightSquare)
        return .visitChildren
    }

    private func record(_ open: TokenSyntax, _ close: TokenSyntax) {
        let start = open.endPositionBeforeTrailingTrivia.utf8Offset
        let end = close.positionAfterSkippingLeadingTrivia.utf8Offset
        if start < end { regions.append(start ..< end) }
    }
}

// Removes up to `dedent` leading spaces from every line after the first.
private func dedentingContinuationLines(_ text: String, by dedent: Int) -> String {
    guard dedent > 0 else { return text }

    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    let pulled = lines.enumerated().map { index, line -> Substring in
        guard index > 0 else { return line }

        var removed = 0
        while removed < dedent, line.dropFirst(removed).first == " " { removed += 1 }
        return line.dropFirst(removed)
    }
    return pulled.joined(separator: "\n")
}

// MARK: Multi-argument calls that fit on one line

// Collapses every exploded multi-argument call whose whole one-line form fits within `lineLength` —
// `foo(\n    a,\n    b\n)` becomes `foo(a, b)` — because the style keeps a call on one line whenever it fits,
// and swift-format (which respects existing line breaks) leaves a hand-broken call broken. Single-argument
// calls are already handled by `unwrappedSingleArgumentCalls`; this owns arity ≥ 2. It runs as a string
// fixpoint pass (re-parsing per edit) so a collapsed inner call lets an enclosing one collapse next round.
private func collapsedFittingCalls(_ source: String) -> String {
    var source = source
    while true {
        let tree = Parser.parse(source: source)
        let bytes = Array(source.utf8)
        let converter = SourceLocationConverter(fileName: "", tree: tree)

        let collector = CallCollector(viewMode: .sourceAccurate)
        collector.walk(tree)

        guard
            let plan = collector.calls.lazy
                .compactMap({ fitPlan($0, bytes: bytes, converter: converter) })
                .first
        else { return source }

        source = splice(source, plan.range, with: plan.text)
    }
}

// The byte range to replace and its single-line replacement, when `call` is an exploded multi-argument call
// that collapses to a line within the limit; nil otherwise (single/zero argument, a trailing closure, already
// one line, a multi-line argument, an interior comment, or the collapsed line would exceed `lineLength`).
private func fitPlan(
    _ call: FunctionCallExprSyntax,
    bytes: [UInt8],
    converter: SourceLocationConverter
) -> (range: Range<Int>, text: String)? {
    guard
        let leftParen = call.leftParen,
        let rightParen = call.rightParen,
        call.trailingClosure == nil,
        call.additionalTrailingClosures.isEmpty,
        call.arguments.count >= 2
    else { return nil }

    // Only act on a call that is actually exploded (a line break between its parens).
    let interior =
        leftParen.endPositionBeforeTrailingTrivia.utf8Offset
        ..< rightParen.positionAfterSkippingLeadingTrivia.utf8Offset
    guard bytes[interior].contains(0x0A) else { return nil }
    // A comment anywhere in the argument list can't survive flattening (a line comment would swallow the rest;
    // a block comment would reflow) — leave the call exploded.
    guard !containsComment(call.arguments) else { return nil }

    let calledText = call.calledExpression.trimmedDescription
    guard !calledText.contains("\n") else { return nil }

    var argumentTexts: [String] = []
    for argument in call.arguments {
        let text = argument.with(\.trailingComma, nil).trimmedDescription
        guard !text.contains("\n") else { return nil }

        argumentTexts.append(text)
    }
    let newCall = calledText + "(" + argumentTexts.joined(separator: ", ") + ")"

    // The collapsed line = columns before the call + the one-line call + whatever currently trails the call's
    // last line after `)`. Measure the whole thing so a too-long collapse (which swift-format would just
    // re-break) is never produced.
    let startColumn = converter.location(for: call.positionAfterSkippingLeadingTrivia).column
    let callEnd = call.endPositionBeforeTrailingTrivia.utf8Offset
    var trailing = 0
    while callEnd + trailing < bytes.count, bytes[callEnd + trailing] != 0x0A { trailing += 1 }
    guard (startColumn - 1) + newCall.count + trailing <= lineLength else { return nil }

    return (call.positionAfterSkippingLeadingTrivia.utf8Offset ..< callEnd, newCall)
}

// True when any token of `node` carries a comment in its leading or trailing trivia.
private func containsComment(_ node: some SyntaxProtocol) -> Bool {
    for token in node.tokens(viewMode: .sourceAccurate) {
        if token.leadingTrivia.contains(where: \.isComment) || token.trailingTrivia.contains(where: \.isComment) {
            return true
        }
    }
    return false
}
