//
//  FormattingHelpers.swift
//  SwiftFormat
//
//  Created by Nick Lockwood on 16/08/2020.
//  Copyright © 2020 Nick Lockwood. All rights reserved.
//

import Foundation

// MARK: shared helper methods

extension Formatter {
    // remove self if possible
    func removeSelf(at i: Int, localNames: Set<String>) -> Bool {
        assert(tokens[i] == .identifier("self"))
        guard let dotIndex = index(of: .nonSpaceOrLinebreak, after: i, if: {
            $0 == .operator(".", .infix)
        }), let nextIndex = index(of: .nonSpaceOrLinebreak, after: dotIndex, if: {
            $0.isIdentifier && !localNames.contains($0.unescaped())
        }), !backticksRequired(at: nextIndex, ignoreLeadingDot: true) else {
            return false
        }
        removeTokens(in: i ..< nextIndex)
        return true
    }

    // Shared wrap implementation
    func wrapCollectionsAndArguments(completePartialWrapping: Bool, wrapSingleArguments: Bool) {
        let maxWidth = options.maxWidth
        func removeLinebreakBeforeEndOfScope(at endOfScope: inout Int) {
            guard let lastIndex = index(of: .nonSpace, before: endOfScope, if: {
                $0.isLinebreak
            }) else {
                return
            }
            if case .commentBody? = last(.nonSpace, before: lastIndex) {
                return
            }
            // Remove linebreak
            removeTokens(in: lastIndex ..< endOfScope)
            endOfScope = lastIndex
            // Remove trailing comma
            if let prevCommaIndex = index(of: .nonSpaceOrCommentOrLinebreak, before: endOfScope, if: {
                $0 == .delimiter(",")
            }) {
                removeToken(at: prevCommaIndex)
                endOfScope -= 1
            }
        }

        func keepParameterLabelsOnSameLine(startOfScope i: Int, endOfScope: inout Int) {
            var endIndex = endOfScope
            while let index = self.lastIndex(of: .linebreak, in: i + 1 ..< endIndex) {
                endIndex = index
                // Check if this linebreak sits between two identifiers
                // (e.g. the external and internal argument labels)
                guard let lastIndex = self.index(of: .nonSpaceOrLinebreak, before: index, if: {
                    $0.isIdentifier
                }), let nextIndex = self.index(of: .nonSpaceOrLinebreak, after: index, if: {
                    $0.isIdentifier
                }) else {
                    continue
                }
                // Remove linebreak
                let range = lastIndex + 1 ..< nextIndex
                let linebreakAndIndent = tokens[index ..< nextIndex]
                replaceTokens(in: range, with: .space(" "))
                endOfScope -= (range.count - 1)
                // Insert replacement linebreak after next comma
                if let nextComma = self.index(of: .delimiter(","), after: index) {
                    if token(at: nextComma + 1)?.isSpace == true {
                        replaceToken(at: nextComma + 1, with: linebreakAndIndent)
                        endOfScope += linebreakAndIndent.count - 1
                    } else {
                        insert(Array(linebreakAndIndent), at: nextComma + 1)
                        endOfScope += linebreakAndIndent.count
                    }
                }
            }
        }

        func wrapArgumentsBeforeFirst(startOfScope i: Int,
                                      endOfScope: Int,
                                      allowGrouping: Bool,
                                      endOfScopeOnSameLine: Bool)
        {
            // Get indent
            let indent = indentForLine(at: i)
            var endOfScope = endOfScope

            keepParameterLabelsOnSameLine(startOfScope: i,
                                          endOfScope: &endOfScope)

            if endOfScopeOnSameLine {
                removeLinebreakBeforeEndOfScope(at: &endOfScope)
            } else {
                // Insert linebreak before closing paren
                if let lastIndex = self.index(of: .nonSpace, before: endOfScope) {
                    endOfScope += insertSpace(indent, at: lastIndex + 1)
                    if !tokens[lastIndex].isLinebreak {
                        insertLinebreak(at: lastIndex + 1)
                        endOfScope += 1
                    }
                }
            }

            // Insert linebreak after each comma
            var index = self.index(of: .nonSpaceOrCommentOrLinebreak, before: endOfScope)!
            if tokens[index] != .delimiter(",") {
                index += 1
            }
            while let commaIndex = self.lastIndex(of: .delimiter(","), in: i + 1 ..< index),
                var linebreakIndex = self.index(of: .nonSpaceOrComment, after: commaIndex)
            {
                if let index = self.index(of: .nonSpace, before: linebreakIndex) {
                    linebreakIndex = index + 1
                }
                if !isCommentedCode(at: linebreakIndex + 1) {
                    if tokens[linebreakIndex].isLinebreak, !options.truncateBlankLines ||
                        next(.nonSpace, after: linebreakIndex).map({ !$0.isLinebreak }) ?? false
                    {
                        insertSpace(indent + options.indent, at: linebreakIndex + 1)
                    } else if !allowGrouping || (maxWidth > 0 &&
                        lineLength(at: linebreakIndex) > maxWidth &&
                        lineLength(upTo: linebreakIndex) <= maxWidth)
                    {
                        insertLinebreak(at: linebreakIndex)
                        insertSpace(indent + options.indent, at: linebreakIndex + 1)
                    }
                }
                index = commaIndex
            }
            // Insert linebreak and indent after opening paren
            if let nextIndex = self.index(of: .nonSpaceOrComment, after: i) {
                if !tokens[nextIndex].isLinebreak {
                    insertLinebreak(at: nextIndex)
                }
                if nextIndex + 1 < endOfScope {
                    var indent = indent
                    if (self.index(of: .nonSpace, after: nextIndex) ?? 0) < endOfScope {
                        indent += options.indent
                    }
                    insertSpace(indent, at: nextIndex + 1)
                }
            }
        }
        func wrapArgumentsAfterFirst(startOfScope i: Int, endOfScope: Int, allowGrouping: Bool) {
            guard var firstArgumentIndex = self.index(of: .nonSpaceOrLinebreak, in: i + 1 ..< endOfScope) else {
                return
            }

            var endOfScope = endOfScope
            keepParameterLabelsOnSameLine(startOfScope: i,
                                          endOfScope: &endOfScope)

            // Remove linebreak after opening paren
            removeTokens(in: i + 1 ..< firstArgumentIndex)
            endOfScope -= (firstArgumentIndex - (i + 1))
            firstArgumentIndex = i + 1
            // Get indent
            let start = startOfLine(at: i)
            let indent = spaceEquivalentToTokens(from: start, upTo: firstArgumentIndex)
            removeLinebreakBeforeEndOfScope(at: &endOfScope)
            // Insert linebreak after each comma
            var lastBreakIndex: Int?
            var index = firstArgumentIndex
            while let commaIndex = self.index(of: .delimiter(","), in: index ..< endOfScope),
                var linebreakIndex = self.index(of: .nonSpaceOrComment, after: commaIndex)
            {
                if let index = self.index(of: .nonSpace, before: linebreakIndex) {
                    linebreakIndex = index + 1
                }
                if maxWidth > 0, lineLength(upTo: commaIndex) >= maxWidth, let breakIndex = lastBreakIndex {
                    endOfScope += 1 + insertSpace(indent, at: breakIndex)
                    insertLinebreak(at: breakIndex)
                    lastBreakIndex = nil
                    index = commaIndex + 1
                    continue
                }
                if tokens[linebreakIndex].isLinebreak {
                    if linebreakIndex + 1 != endOfScope, !isCommentedCode(at: linebreakIndex + 1) {
                        endOfScope += insertSpace(indent, at: linebreakIndex + 1)
                    }
                } else if !allowGrouping {
                    insertLinebreak(at: linebreakIndex)
                    endOfScope += 1 + insertSpace(indent, at: linebreakIndex + 1)
                } else {
                    lastBreakIndex = linebreakIndex
                }
                index = commaIndex + 1
            }
            if maxWidth > 0, let breakIndex = lastBreakIndex, lineLength(at: breakIndex) > maxWidth {
                insertSpace(indent, at: breakIndex)
                insertLinebreak(at: breakIndex)
            }
        }

        var lastIndex = -1
        forEachToken(onlyWhereEnabled: false) { i, token in
            guard case let .startOfScope(string) = token else {
                return
            }
            guard ["(", "[", "<"].contains(string) else {
                lastIndex = i
                return
            }

            if lastIndex < i, let i = (lastIndex + 1 ..< i).last(where: {
                tokens[$0].isLinebreak
            }) {
                lastIndex = i
            }

            guard let endOfScope = endOfScope(at: i) else {
                return
            }

            let mode: WrapMode
            var endOfScopeOnSameLine = false
            let hasMultipleArguments = index(of: .delimiter(","), in: i + 1 ..< endOfScope) != nil
            var isParameters = false
            switch string {
            case "(":
                /// Don't wrap color/image literals due to Xcode bug
                guard let prevToken = self.token(at: i - 1),
                    prevToken != .keyword("#colorLiteral"),
                    prevToken != .keyword("#imageLiteral")
                else {
                    return
                }
                guard hasMultipleArguments || wrapSingleArguments ||
                    index(in: i + 1 ..< endOfScope, where: { $0.isComment }) != nil
                else {
                    // Not an argument list, or only one argument
                    lastIndex = i
                    return
                }

                endOfScopeOnSameLine = options.closingParenOnSameLine
                isParameters = isParameterList(at: i)
                if isParameters, options.wrapParameters != .default {
                    mode = options.wrapParameters
                } else {
                    mode = options.wrapArguments
                }
            case "<":
                mode = options.wrapArguments
            case "[":
                mode = options.wrapCollections
            default:
                return
            }
            guard mode != .disabled, let firstIdentifierIndex =
                index(of: .nonSpaceOrCommentOrLinebreak, after: i),
                !isStringLiteral(at: i)
            else {
                lastIndex = i
                return
            }

            guard isEnabled else {
                lastIndex = i
                return
            }

            if completePartialWrapping,
                let firstLinebreakIndex = index(of: .linebreak, in: i + 1 ..< endOfScope)
            {
                switch mode {
                case .beforeFirst:
                    wrapArgumentsBeforeFirst(startOfScope: i,
                                             endOfScope: endOfScope,
                                             allowGrouping: firstIdentifierIndex > firstLinebreakIndex,
                                             endOfScopeOnSameLine: endOfScopeOnSameLine)
                case .preserve where firstIdentifierIndex > firstLinebreakIndex:
                    wrapArgumentsBeforeFirst(startOfScope: i,
                                             endOfScope: endOfScope,
                                             allowGrouping: true,
                                             endOfScopeOnSameLine: endOfScopeOnSameLine)
                case .afterFirst, .preserve:
                    wrapArgumentsAfterFirst(startOfScope: i,
                                            endOfScope: endOfScope,
                                            allowGrouping: true)
                case .disabled, .default:
                    assertionFailure() // Shouldn't happen
                }

            } else if maxWidth > 0, hasMultipleArguments || wrapSingleArguments {
                func willWrapAtStartOfReturnType(maxWidth: Int) -> Bool {
                    return isInReturnType(at: i) && maxWidth < lineLength(at: i)
                }

                func startOfNextScopeNotInReturnType() -> Int? {
                    let endOfLine = self.endOfLine(at: i)
                    guard endOfScope < endOfLine else { return nil }

                    var startOfLastScopeOnLine = endOfScope

                    repeat {
                        guard let startOfNextScope = index(
                            of: .startOfScope,
                            in: startOfLastScopeOnLine + 1 ..< endOfLine
                        ) else {
                            return nil
                        }

                        startOfLastScopeOnLine = startOfNextScope
                    } while isInReturnType(at: startOfLastScopeOnLine)

                    return startOfLastScopeOnLine
                }

                func indexOfNextWrap() -> Int? {
                    let startOfNextScopeOnLine = startOfNextScopeNotInReturnType()
                    let nextNaturalWrap = indexWhereLineShouldWrap(from: endOfScope + 1)

                    switch (startOfNextScopeOnLine, nextNaturalWrap) {
                    case let (.some(startOfNextScopeOnLine), .some(nextNaturalWrap)):
                        return min(startOfNextScopeOnLine, nextNaturalWrap)
                    case let (nil, .some(nextNaturalWrap)):
                        return nextNaturalWrap
                    case let (.some(startOfNextScopeOnLine), nil):
                        return startOfNextScopeOnLine
                    case (nil, nil):
                        return nil
                    }
                }

                func wrapArgumentsWithoutPartialWrapping() {
                    switch mode {
                    case .preserve, .beforeFirst:
                        wrapArgumentsBeforeFirst(startOfScope: i,
                                                 endOfScope: endOfScope,
                                                 allowGrouping: false,
                                                 endOfScopeOnSameLine: endOfScopeOnSameLine)
                    case .afterFirst:
                        wrapArgumentsAfterFirst(startOfScope: i,
                                                endOfScope: endOfScope,
                                                allowGrouping: true)
                    case .disabled, .default:
                        assertionFailure() // Shouldn't happen
                    }
                }

                if currentRule == FormatRules.wrap {
                    let nextWrapIndex = indexOfNextWrap() ?? endOfLine(at: i)
                    if nextWrapIndex > lastIndex,
                        maxWidth < lineLength(from: max(lastIndex, 0), upTo: nextWrapIndex),
                        !willWrapAtStartOfReturnType(maxWidth: maxWidth)
                    {
                        wrapArgumentsWithoutPartialWrapping()
                        lastIndex = nextWrapIndex
                        return
                    }
                } else if maxWidth < lineLength(upTo: endOfScope) {
                    wrapArgumentsWithoutPartialWrapping()
                }
            }

            lastIndex = i
        }
    }

    func removeParen(at index: Int) {
        func tokenOutsideParenRequiresSpacing(at index: Int) -> Bool {
            guard let token = self.token(at: index) else { return false }
            switch token {
            case .identifier, .keyword, .number, .startOfScope("#if"):
                return true
            default:
                return false
            }
        }

        func tokenInsideParenRequiresSpacing(at index: Int) -> Bool {
            guard let token = self.token(at: index) else { return false }
            switch token {
            case .operator, .startOfScope("{"), .endOfScope("}"):
                return true
            default:
                return tokenOutsideParenRequiresSpacing(at: index)
            }
        }

        if token(at: index - 1)?.isSpace == true,
            token(at: index + 1)?.isSpace == true
        {
            // Need to remove one
            removeToken(at: index + 1)
        } else if case .startOfScope = tokens[index] {
            if tokenOutsideParenRequiresSpacing(at: index - 1),
                tokenInsideParenRequiresSpacing(at: index + 1)
            {
                // Need to insert one
                insert(.space(" "), at: index + 1)
            }
        } else if tokenInsideParenRequiresSpacing(at: index - 1),
            tokenOutsideParenRequiresSpacing(at: index + 1)
        {
            // Need to insert one
            insert(.space(" "), at: index + 1)
        }
        removeToken(at: index)
    }

    /// Recursively organizes the body declarations of this declaration and any nested types.
    func organizeDeclarations(_ declaration: Declaration) -> Formatter.Declaration {
        switch declaration {
        case let .type(kind, open, body, close):
            // Organize the body of this type
            let (_, organizedOpen, organizedBody, organizedClose) = organizeType((kind, open, body, close))

            // And also organize any of its nested children
            return .type(
                kind: kind,
                open: organizedOpen,
                body: organizedBody.map { organizeDeclarations($0) },
                close: organizedClose
            )

        // We don't organize declarations within conditional compilation blocks
        // since they represent their own scope, but we still need to organize
        // the body of any _types_ inside this block.
        case let .conditionalCompilation(open, body, close):
            return .conditionalCompilation(
                open: open,
                body: body.map { organizeDeclarations($0) },
                close: close
            )

        // If the declaration doesn't have a body, there isn't any work to do
        case .declaration:
            return declaration
        }
    }
}

// Utility functions used by organizeDeclarations rule
// TODO: find a better place to put this
private extension Formatter {
    /// Categories of declarations within an individual type
    enum Category: String, CaseIterable {
        case beforeMarks
        case lifecycle
        case open
        case `public`
        case `internal`
        case `fileprivate`
        case `private`

        /// The comment tokens that should precede all declarations in this category
        func markComment(from template: String) -> String? {
            switch self {
            case .beforeMarks:
                return nil
            default:
                return "// \(template.replacingOccurrences(of: "%c", with: rawValue.capitalized))"
            }
        }
    }

    /// Types of declarations that can be present within an individual category
    enum DeclarationType {
        case nestedType
        case staticProperty
        case staticPropertyWithBody
        case classPropertyWithBody
        case instanceProperty
        case instancePropertyWithBody
        case staticMethod
        case classMethod
        case instanceMethod
    }

    static let categoryOrdering: [Category] = [
        .beforeMarks, .lifecycle, .open, .public, .internal, .fileprivate, .private,
    ]

    static let categorySubordering: [DeclarationType] = [
        .nestedType, .staticProperty, .staticPropertyWithBody, .classPropertyWithBody,
        .instanceProperty, .instancePropertyWithBody, .staticMethod, .classMethod, .instanceMethod,
    ]

    /// The `Category` of the given `Declaration`
    func category(of declaration: Formatter.Declaration) -> Category {
        switch declaration {
        case let .declaration(keyword, tokens), let .type(keyword, open: tokens, _, _):
            let parser = Formatter(tokens)

            guard let keywordIndex = parser.index(after: -1, where: { $0.string == keyword }) else {
                // This should never happen (the declaration's `keyword` will always be present in the tokens)
                return .internal
            }

            // Enum cases don't fit into any of the other categories,
            // so they should go in the intial top section.
            //  - The user can also provide other declaration types to place in this category
            if declaration.keyword == "case" || options.beforeMarks.contains(declaration.keyword) {
                return .beforeMarks
            }

            if Formatter.categoryOrdering.contains(.lifecycle) {
                // `init` and `deinit` always go in Lifecycle if it's present
                if ["init", "deinit"].contains(keyword) {
                    return .lifecycle
                }

                // The user can also provide specific instance method names to place in Lifecycle
                //  - In the function declaration grammar, the function name always
                //    immediately follows the `func` keyword:
                //    https://docs.swift.org/swift-book/ReferenceManual/Declarations.html#grammar_function-name
                if keyword == "func",
                    let methodName = parser.next(.nonSpaceOrCommentOrLinebreak, after: keywordIndex),
                    options.lifecycleMethods.contains(methodName.string)
                {
                    return .lifecycle
                }
            }

            // Search for a visibility keyword in the tokens before the primary keyword,
            // making sure we exclude groups like private(set).
            var searchIndex = 0

            while searchIndex < keywordIndex {
                if let visibilityCategory = Category(rawValue: parser.tokens[searchIndex].string),
                    parser.next(.nonSpaceOrComment, after: searchIndex) != .startOfScope("(")
                {
                    return visibilityCategory
                }

                searchIndex += 1
            }

            // `internal` is the default implied vibilility if no other is specified
            return .internal

        case let .conditionalCompilation(_, body, _):
            // Conditional compilation blocks themselves don't have a category or visbility-level,
            // but we still have to assign them a category for the sorting algorithm to function.
            // A reasonable heuristic here is to simply use the category of the first declaration
            // inside the conditional compilation block.
            if let firstDeclarationInBlock = body.first {
                return category(of: firstDeclarationInBlock)
            } else {
                return .beforeMarks
            }
        }
    }

    /// The `DeclarationType` of the given `Declaration`
    func type(of declaration: Declaration) -> DeclarationType? {
        switch declaration {
        case .type:
            return .nestedType

        case let .declaration(keyword, tokens):
            let declarationParser = Formatter(tokens)

            guard let declarationTypeTokenIndex = declarationParser.index(
                after: -1,
                where: { $0.isKeyword && $0.string == keyword }
            )
            else { return nil }

            let declarationTypeToken = declarationParser.tokens[declarationTypeTokenIndex]

            let isStaticDeclaration = declarationParser.lastToken(
                before: declarationTypeTokenIndex,
                where: { $0 == .keyword("static") }
            ) != nil

            let isClassDeclaration = declarationParser.lastToken(
                before: declarationTypeTokenIndex,
                where: { $0 == .keyword("class") }
            ) != nil

            switch declarationTypeToken {
            // Properties and property-like declarations
            case .keyword("let"), .keyword("var"),
                 .keyword("case"), .keyword("operator"), .keyword("precedencegroup"):

                var hasBody: Bool
                // If there is a code block at the end of the declaration that is _not_ a closure,
                // then this declaration has a body.
                if let lastClosingBraceIndex = declarationParser.index(of: .endOfScope("}"), before: declarationParser.tokens.count),
                    let lastOpeningBraceIndex = declarationParser.index(of: .startOfScope("{"), before: lastClosingBraceIndex),
                    declarationTypeTokenIndex < lastOpeningBraceIndex,
                    declarationTypeTokenIndex < lastClosingBraceIndex,
                    !declarationParser.isStartOfClosure(at: lastOpeningBraceIndex)
                {
                    hasBody = true
                } else {
                    hasBody = false
                }

                if isStaticDeclaration {
                    if hasBody {
                        return .staticPropertyWithBody
                    } else {
                        return .staticProperty
                    }
                } else if isClassDeclaration {
                    // Interestingly, Swift does not support stored class properties
                    // so there's no such thing as a class property without a body.
                    // https://forums.swift.org/t/class-properties/16539/11
                    return .classPropertyWithBody
                } else {
                    if hasBody {
                        return .instancePropertyWithBody
                    } else {
                        return .instanceProperty
                    }
                }

            // Functions and function-like declarations
            case .keyword("func"), .keyword("init"), .keyword("deinit"), .keyword("subscript"):
                if isStaticDeclaration {
                    return .staticMethod
                } else if isClassDeclaration {
                    return .classMethod
                } else {
                    return .instanceMethod
                }

            // Type-like declarations
            case .keyword("typealias"):
                return .nestedType

            default:
                return nil
            }

        case .conditionalCompilation:
            return nil
        }
    }

    /// Updates the given declaration tokens so it ends with at least one blank like
    /// (e.g. so it ends with at least two newlines)
    func endingWithBlankLine(_ tokens: [Token]) -> [Token] {
        let parser = Formatter(tokens)

        // Determine how many trailing linebreaks there are in this declaration
        var numberOfTrailingLinebreaks = 0
        var searchIndex = parser.tokens.count - 1

        while searchIndex > 0,
            let token = parser.token(at: searchIndex),
            token.isSpaceOrCommentOrLinebreak
        {
            if token.isLinebreak {
                numberOfTrailingLinebreaks += 1
            }

            searchIndex -= 1
        }

        // Make sure there are atleast two newlines,
        // so we get a blank line between individual declaration types
        while numberOfTrailingLinebreaks < 2 {
            parser.insertLinebreak(at: parser.tokens.count)
            numberOfTrailingLinebreaks += 1
        }

        return parser.tokens
    }

    /// Removes any existing category separators from the given declarations
    func removeExistingCategorySeparators(from typeBody: [Formatter.Declaration]) -> [Formatter.Declaration] {
        var typeBody = typeBody

        for (declarationIndex, declaration) in typeBody.enumerated() {
            let tokensToInspect: [Token]
            switch declaration {
            case let .declaration(_, tokens):
                tokensToInspect = tokens
            case let .type(_, open, _, _), let .conditionalCompilation(open, _, _):
                // Only inspect the opening tokens of declarations with a body
                tokensToInspect = open
            }

            let potentialCategorySeparators = Category.allCases.flatMap {
                Array(Set([
                    // The user's specific category separator template
                    $0.markComment(from: options.categoryMarkComment),
                    // Other common variants that we would want to replace with the correct variant
                    $0.markComment(from: "%c"),
                    $0.markComment(from: "// MARK: %c"),
                ]))
            }.compactMap { $0 }

            let parser = Formatter(tokensToInspect)

            parser.forEach(.startOfScope("//")) { commentStartIndex, _ in
                // Only look at top-level comments inside of the type body
                guard parser.currentScope(at: commentStartIndex) == nil else {
                    return
                }

                // Check if this comment matches an expected category separator comment
                for potentialSeparatorComment in potentialCategorySeparators {
                    let potentialCategorySeparator = tokenize(potentialSeparatorComment)
                    let potentialSeparatorRange = commentStartIndex ..< (commentStartIndex + potentialCategorySeparator.count)

                    guard parser.tokens.indices.contains(potentialSeparatorRange.upperBound),
                        let nextNonwhitespaceIndex = parser.index(of: .nonSpaceOrLinebreak, after: potentialSeparatorRange.upperBound)
                    else { continue }

                    // Check the edit distance of this existing comment with the potential
                    // valid category separators for this category. If they are similar or identical,
                    // we'll want to replace the existing comment with the correct comment.
                    let existingComment = sourceCode(for: Array(parser.tokens[potentialSeparatorRange]))
                    let minimumEditDistance = Int(0.2 * Float(existingComment.count))

                    guard editDistance(existingComment.lowercased(), potentialSeparatorComment.lowercased())
                        <= minimumEditDistance
                    else { continue }

                    // Makes sure there are only whitespace or other comments before this comment.
                    // Otherwise, we don't want to remove it.
                    let tokensBeforeComment = parser.tokens[0 ..< commentStartIndex]
                    guard !tokensBeforeComment.contains(where: { !$0.isSpaceOrCommentOrLinebreak }) else {
                        continue
                    }

                    // If we found a matching comment, remove it and all subsequent empty lines
                    let startOfCommentLine = parser.startOfLine(at: commentStartIndex)
                    let startOfNextDeclaration = parser.startOfLine(at: nextNonwhitespaceIndex)
                    parser.removeTokens(in: startOfCommentLine ..< startOfNextDeclaration)

                    // Move any tokens from before the category separator into the previous declaration.
                    // This makes sure that things like comments stay grouped in the same category.
                    if declarationIndex != 0, startOfCommentLine != 0 {
                        // Remove the tokens before the category separator from this declaration...
                        let rangeBeforeComment = 0 ..< startOfCommentLine
                        let tokensBeforeCommentLine = Array(parser.tokens[rangeBeforeComment])
                        parser.removeTokens(in: rangeBeforeComment)

                        // ... and append them to the end of the previous declaration
                        switch typeBody[declarationIndex - 1] {
                        case let .declaration(kind, tokens):
                            typeBody[declarationIndex - 1] = .declaration(
                                kind: kind,
                                tokens: tokens + tokensBeforeCommentLine
                            )

                        case let .type(kind, open, body, close):
                            typeBody[declarationIndex - 1] = .type(
                                kind: kind,
                                open: open,
                                body: body,
                                close: close + tokensBeforeCommentLine
                            )

                        case let .conditionalCompilation(open, body, close):
                            typeBody[declarationIndex - 1] = .conditionalCompilation(
                                open: open,
                                body: body,
                                close: close + tokensBeforeCommentLine
                            )
                        }
                    }

                    // Apply the updated tokens back to this declaration
                    switch typeBody[declarationIndex] {
                    case let .declaration(kind, _):
                        typeBody[declarationIndex] = .declaration(
                            kind: kind,
                            tokens: parser.tokens
                        )

                    case let .type(kind, _, body, close):
                        typeBody[declarationIndex] = .type(
                            kind: kind,
                            open: parser.tokens,
                            body: body,
                            close: close
                        )

                    case let .conditionalCompilation(_, body, close):
                        typeBody[declarationIndex] = .conditionalCompilation(
                            open: parser.tokens,
                            body: body,
                            close: close
                        )
                    }
                }
            }
        }

        return typeBody
    }

    /// Organizes the flat list of declarations based on category and type
    func organizeType(
        _ typeDeclaration: (kind: String, open: [Token], body: [Formatter.Declaration], close: [Token])
    ) -> (kind: String, open: [Token], body: [Formatter.Declaration], close: [Token]) {
        // Only organize the body of classes, structs, and enums (not protocols and extensions)
        guard ["class", "struct", "enum"].contains(typeDeclaration.kind) else {
            return typeDeclaration
        }

        // Make sure this type's body is longer than the organization threshold
        let organizationThreshold: Int
        switch typeDeclaration.kind {
        case "class":
            organizationThreshold = options.organizeClassThreshold
        case "struct":
            organizationThreshold = options.organizeStructThreshold
        case "enum":
            organizationThreshold = options.organizeEnumThreshold
        default:
            organizationThreshold = 0
        }

        // Count the number of lines in this declaration
        let lineCount = typeDeclaration.body
            .flatMap { $0.tokens }
            .filter { $0.isLinebreak }
            .count

        // Don't organize this type's body if it is shorter than the minimum organization threshold
        if lineCount < organizationThreshold {
            return typeDeclaration
        }

        var typeOpeningTokens = typeDeclaration.open
        let typeClosingTokens = typeDeclaration.close

        // Remove all of the existing category separators, so they can be readded
        // at the correct location after sorting the declarations.
        let bodyWithoutCategorySeparators = removeExistingCategorySeparators(from: typeDeclaration.body)

        // Categorize each of the declarations into their primary groups
        typealias CategorizedDeclarations = [(declaration: Formatter.Declaration, category: Category, type: DeclarationType?)]

        let categorizedDeclarations = bodyWithoutCategorySeparators.map {
            (declaration: $0, category: category(of: $0), type: type(of: $0))
        }

        /// Sorts the given categoried declarations based on their derived metadata
        func sortDeclarations(
            _ declarations: CategorizedDeclarations,
            byCategory sortByCategory: Bool,
            byType sortByType: Bool
        ) -> CategorizedDeclarations {
            return declarations.enumerated()
                .sorted(by: { lhs, rhs in
                    let (lhsOriginalIndex, lhs) = lhs
                    let (rhsOriginalIndex, rhs) = rhs

                    // Sort primarily by category
                    if sortByCategory,
                        let lhsCategorySortOrder = Formatter.categoryOrdering.index(of: lhs.category),
                        let rhsCategorySortOrder = Formatter.categoryOrdering.index(of: rhs.category),
                        lhsCategorySortOrder != rhsCategorySortOrder
                    {
                        return lhsCategorySortOrder < rhsCategorySortOrder
                    }

                    // Within individual categories (excluding .beforeMarks), sort by the declaration type
                    if sortByType,
                        lhs.category != .beforeMarks,
                        rhs.category != .beforeMarks,
                        let lhsType = lhs.type,
                        let rhsType = rhs.type,
                        let lhsTypeSortOrder = Formatter.categorySubordering.index(of: lhsType),
                        let rhsTypeSortOrder = Formatter.categorySubordering.index(of: rhsType),
                        lhsTypeSortOrder != rhsTypeSortOrder
                    {
                        return lhsTypeSortOrder < rhsTypeSortOrder
                    }

                    // Respect the original declaration ordering when the categories and types are the same
                    return lhsOriginalIndex < rhsOriginalIndex
                })
                .map { $0.element }
        }

        // Sort the declarations based on their category and type
        var sortedDeclarations = sortDeclarations(categorizedDeclarations, byCategory: true, byType: true)

        // The compiler will synthesize a memberwise init for `struct`
        // declarations that don't have an `init` declaration.
        // We have to take care to not reorder any properties (but reordering functions etc is ok!)
        if typeDeclaration.kind == "struct",
            !typeDeclaration.body.contains(where: { $0.keyword == "init" })
        {
            /// Whether or not this declaration is an instance property that can affect
            /// the parameters struct's synthesized memberwise initializer
            func affectsSynthesizedMemberwiseInitializer(
                _ declaration: Formatter.Declaration,
                _ type: DeclarationType?
            ) -> Bool {
                switch type {
                case .instanceProperty?:
                    return true

                case .instancePropertyWithBody?:
                    // `instancePropertyWithBody` represents some stored properties,
                    // but also computed properties. Only stored properties,
                    // not computed properties, affect the synthesized init.
                    //
                    // This is a stored property if and only if
                    // the declaration body has a `didSet` or `willSet` keyword,
                    // based on the grammar for a variable declaration:
                    // https://docs.swift.org/swift-book/ReferenceManual/Declarations.html#grammar_variable-declaration
                    let parser = Formatter(declaration.tokens)
                    var hasWillSetOrDidSetBlock = false

                    if let bodyOpenBrace = parser.index(of: .startOfScope("{"), after: -1),
                        let firstBodyToken = parser.next(.nonSpaceOrCommentOrLinebreak, after: bodyOpenBrace),
                        firstBodyToken.string == "willSet" || firstBodyToken.string == "didSet"
                    {
                        hasWillSetOrDidSetBlock = true
                    }

                    return hasWillSetOrDidSetBlock

                default:
                    return false
                }
            }

            // Whether or not the two given declaration orderings preserve
            // the same synthesized memberwise initializer
            func preservesSynthesizedMemberwiseInitiaizer(
                _ lhs: CategorizedDeclarations,
                _ rhs: CategorizedDeclarations
            ) -> Bool {
                let lhsPropertiesOrder = lhs
                    .filter { affectsSynthesizedMemberwiseInitializer($0.declaration, $0.type) }
                    .map { $0.declaration }

                let rhsPropertiesOrder = rhs
                    .filter { affectsSynthesizedMemberwiseInitializer($0.declaration, $0.type) }
                    .map { $0.declaration }

                return lhsPropertiesOrder == rhsPropertiesOrder
            }

            if !preservesSynthesizedMemberwiseInitiaizer(categorizedDeclarations, sortedDeclarations) {
                // If sorting by category and by type could cause compilation failures
                // by not correctly preserving the synthesized memberwise initializer,
                // try to sort _only_ by category (so we can try to preserve the correct category separators)
                sortedDeclarations = sortDeclarations(categorizedDeclarations, byCategory: true, byType: false)

                // If sorting _only_ by category still changes the synthesized memberwise initializer,
                // then there's nothing we can do to organize this struct.
                if !preservesSynthesizedMemberwiseInitiaizer(categorizedDeclarations, sortedDeclarations) {
                    return typeDeclaration
                }
            }
        }

        // Insert comments to separate the categories
        let numberOfCategories = Formatter.categoryOrdering.filter { category in
            sortedDeclarations.contains(where: { $0.category == category })
        }.count

        for category in Formatter.categoryOrdering {
            guard let indexOfFirstDeclaration = sortedDeclarations
                .firstIndex(where: { $0.category == category })
            else { continue }

            // Build the MARK declaration, but only when there is more than one category present.
            if numberOfCategories > 1,
                let markComment = category.markComment(from: options.categoryMarkComment)
            {
                let firstDeclaration = sortedDeclarations[indexOfFirstDeclaration].declaration
                let declarationParser = Formatter(firstDeclaration.tokens)
                let indentation = declarationParser.indentForLine(at: 0)

                let markDeclaration = tokenize("\(indentation)\(markComment)\n\n")

                sortedDeclarations.insert(
                    (.declaration(kind: "comment", tokens: markDeclaration), category, nil),
                    at: indexOfFirstDeclaration
                )

                // If this declaration is the first declaration in the type scope,
                // make sure the type's opening sequence of tokens ends with
                // at least one blank line so the category separator appears balanced
                if indexOfFirstDeclaration == 0 {
                    typeOpeningTokens = endingWithBlankLine(typeOpeningTokens)
                }
            }

            // Insert newlines to separate declaration types
            for declarationType in Formatter.categorySubordering {
                guard let indexOfLastDeclarationWithType = sortedDeclarations
                    .lastIndex(where: { $0.category == category && $0.type == declarationType }),
                    indexOfLastDeclarationWithType != sortedDeclarations.indices.last
                else { continue }

                switch sortedDeclarations[indexOfLastDeclarationWithType].declaration {
                case let .type(kind, open, body, close):
                    sortedDeclarations[indexOfLastDeclarationWithType].declaration = .type(
                        kind: kind,
                        open: open,
                        body: body,
                        close: endingWithBlankLine(close)
                    )

                case let .declaration(kind, tokens):
                    sortedDeclarations[indexOfLastDeclarationWithType].declaration
                        = .declaration(kind: kind, tokens: endingWithBlankLine(tokens))

                case .conditionalCompilation:
                    break
                }
            }
        }

        return (
            kind: typeDeclaration.kind,
            open: typeOpeningTokens,
            body: sortedDeclarations.map { $0.declaration },
            close: typeClosingTokens
        )
    }
}
