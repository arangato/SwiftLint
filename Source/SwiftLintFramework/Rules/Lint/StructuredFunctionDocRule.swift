import Foundation
import Markdown
import SourceKittenFramework

public struct StructuredFunctionDocRule: ASTRule, OptInRule, ConfigurationProviderRule, AutomaticTestableRule {
    public var configuration = StructuredFunctionDocConfiguration()

    public init() {}

    public static let description = RuleDescription(
        identifier: "structured_function_doc",
        name: "Structured Function Doc",
        description:
            "Function documentation should have a short summary followed by parameters section.",
        kind: .lint,
        minSwiftVersion: .fourDotOne,
        nonTriggeringExamples: StructuredFunctionDocRuleExamples.nonTriggeringExamples,
        triggeringExamples: StructuredFunctionDocRuleExamples.triggeringExamples
    )

    public func validate(file: SwiftLintFile,
                         kind: SwiftDeclarationKind,
                         dictionary: SourceKittenDictionary) -> [StyleViolation] {
        guard
            SwiftDeclarationKind.functionKinds.contains(kind),
            let docOffset = dictionary.docOffset,
            let docLength = dictionary.docLength
        else {
            return []
        }

        let parameterNames = dictionary.substructure.compactMap { subStructure -> String? in
            guard subStructure.declarationKind == .varParameter, let name = subStructure.name else {
                return nil
            }

            return name
        }

        guard parameterNames.count >= configuration.minimalNumberOfParameters else {
            return []
        }

        let docByteRange = ByteRange(location: docOffset, length: docLength)
        guard let docLineRange = file.stringView.lineRangeWithByteRange(docByteRange) else {
            return []
        }
        let docLines = Array(file.stringView.lines[docLineRange.start - 1 ..< docLineRange.end - 1])

        let lineContents = docLines.map {
          $0.content.removingCommonLeadingWhitespaceFromLines().dropFirst(3)
        }.joined(separator: "\n")

        let violation = { (offset: ByteCount) -> [StyleViolation] in
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: offset))
          ]
        }
        let document = Document(parsing: lineContents)
        let markupChildren = Array(document.children)
        guard let summaryParagraph = markupChildren.first as? Markdown.Paragraph else {
          return violation(docOffset)
        }

        if configuration.maxSummaryLineCount > 0 &&
            summaryParagraph.textLines.count > configuration.maxSummaryLineCount {
            return violation(docOffset)
        }

        guard let parametersList = markupChildren.compactMap({ $0 as? Markdown.UnorderedList }).first else {
          return violation(docOffset)
        }

        let parameterFirstLines = Array(parametersList.children)
            .compactMap { $0.child(at: 0) as? Markdown.Paragraph }
            .compactMap { $0.textLines.first }
        let expectedPrefixes = (["Parameters"] + parameterNames).map { $0 + ":" }
        guard expectedPrefixes.count == parameterFirstLines.count else {
            return violation(docOffset)
        }

        for (expectedPrefix, text) in zip(expectedPrefixes, parameterFirstLines) {
            guard text.string.starts(with: expectedPrefix) else {
                guard let lineIndex = text.range?.lowerBound.line else {
                  return violation(docOffset)
                }
                let lineOffset = docLines[lineIndex - 1].byteRange.location
                return violation(lineOffset)
            }
        }

//        print(document.debugDescription(options: .printSourceLocations))
        return []
    }
}

private extension Paragraph {
    var textLines: [Markdown.Text] {
        children.compactMap { $0 as? Markdown.Text }
    }
}
