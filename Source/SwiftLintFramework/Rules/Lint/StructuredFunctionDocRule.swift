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

    private static let characterSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/"))

    private static let missingParametersHeader = "missing '- Parameters:' markdown header"

    private static let parametersSectionHeader = "- Parameters:"

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

        var parameterNames = dictionary.substructure.compactMap { subStructure -> String? in
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

        let document = Document(parsing: lineContents)
        let markupChildren = Array(document.children)
        guard let summaryParagraph = markupChildren.first as? Markdown.Paragraph else {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

        if configuration.maxSummaryLineCount > 0 &&
            getLines(summaryParagraph).count > configuration.maxSummaryLineCount {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

        guard let parametersList = markupChildren.compactMap({ $0 as? Markdown.UnorderedList }).first else {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

        var parameterFirstLines = parametersList.children
            .compactMap { $0 as? Markdown.Paragraph }
            .compactMap { getLines($0).first }
        let firstLine = parameterFirstLines.removeFirst()
        guard firstLine.string.starts(with: "Parameters:") else {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

        print(document.debugDescription(options: .printSourceLocations))
        var visitor = MarkupExtractor()
        visitor.defaultVisit(document)
        let topElements = visitor.visitedElements
        visitor = MarkupExtractor()
        visitor.descendInto(topElements[0])
        let summary = visitor.visitedElements

        visitor = MarkupExtractor()
        visitor.descendInto(topElements[1])
        let listElements = visitor.visitedElements
        let texts: [Markup] = listElements.map {
          visitor = MarkupExtractor()
          visitor.descendInto($0)
          guard let p = visitor.visitedElements.first else { return nil }
          return p
        }.compactMap { $0 }
        .map { (m: Markup) in
          visitor = MarkupExtractor()
          visitor.descendInto(m)
          guard let p = visitor.visitedElements.first else { return nil }
          return p
        }.compactMap { $0 }


        guard let (summary, body) = split(in: docLines), summary.count <= configuration.maxSummaryLineCount else {
            return [
                StyleViolation(ruleDescription: Self.description,
                               severity: configuration.severityConfiguration.severity,
                               location: Location(file: file, byteOffset: docOffset))
            ]
        }

        let parameterLines = removedUpToParameters(lines: body)
        for line in parameterLines {
            let parameterName = parameterNames.removeFirst()
            let lineContent = line.content.trimmingCharacters(in: Self.characterSet)
            if !lineContent.starts(with: "- \(parameterName):") {
                return [
                    StyleViolation(ruleDescription: Self.description,
                                   severity: configuration.severityConfiguration.severity,
                                   location: Location(file: file, byteOffset: line.byteRange.location))
                ]
            }
        }
        if parameterNames.isNotEmpty {
            return [
                StyleViolation(ruleDescription: Self.description,
                               severity: configuration.severityConfiguration.severity,
                               location: Location(file: file, byteOffset: docLines.last!.byteRange.upperBound - 1))
            ]
        }
        return []
    }

    private func split(in lines: [Line]) -> (ArraySlice<Line>, ArraySlice<Line>)? {
        for (index, line) in lines.enumerated() {
            let lineContent = line.content.trimmingCharacters(in: Self.characterSet)
            if lineContent.isEmpty {
                return (lines.prefix(upTo: index), lines.suffix(from: index + 1))
            }
            if lineContent == Self.parametersSectionHeader {
                return (lines.prefix(upTo: index), lines.suffix(from: index))
            }
        }
        return nil
    }

    private func removedUpToParameters(lines: ArraySlice<Line>) -> [Line] {
        var lines = lines
        while let first = lines.popFirst() {
            if first.content.trimmingCharacters(in: Self.characterSet) == Self.parametersSectionHeader {
                break
            }
        }
        return Array(lines)
    }

}

enum MarkupElement {
  case paragraph
  case unorderedList
}
//struct MarkupNode {
//  var markup: Markup
//  var elements: []
//}
//func parse(document: Markup) {
//  for child in document.children {
//    if let paragraph = child as? Paragraph {
//      parse(paragraph)
//    } else if let unorderedList = child as? UnorderedList {
//      parse(unorderedList)
//    }
//  }
//}

func getLines(_ paragraph: Paragraph) -> [Markdown.Text] {
  paragraph.children.compactMap { $0 as? Markdown.Text }
}
func getParagraphs(_ unorderedList: UnorderedList) {
  for e in unorderedList.children {
//    if let paragraph = e as? Paragraph {
//      parse(paragraph)
//    } else if let unorderedList = e as? UnorderedList {
//      parse(unorderedList)
//    }
  }
}

struct MarkupExtractor: MarkupWalker {
  var visitedElements = [Markup]()
  /// Saves changes to the persistent store if the context has uncommitted changes
  ///
  /// - Parameters:
  /// - parameter lastAPISync: Date data from the API was last synced.
  /// - throws: An error is thrown if unsaved context changes cannot be committed to the persistent store
  /// - returns: None
  /// - parameter lastAPISync2: Date data .
  ///
  ///# Notes: #
  /// 1.  If a lastAPISync Date is provided, the lastAPISync date will be added and saved to the managedObjectContext
  /// 2.  If there are no unsaved changes and no lastAPISync date is provided, this function does nothing.
  ///
  /// - parameter lastAPISync3: Date  .
  /// # Example #
  /// ```
  /// // Save after an API sync
  /// let lastAPISync = Date()
  /// save(lastAPISync: lastAPISync)
  /// // Save local changes
  /// save(lastAPISync: nil)
  /// ```
  public mutating func defaultVisit(_ markup: Markup) {
    visitedElements.append(markup)
    if let range = markup.range {
      print(range)
    }
  }

  mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
    descendInto(unorderedList)
  }

  mutating func visitParagraph(_ paragraph: Paragraph) {
    print(paragraph.debugDescription())
    for e in paragraph.children {
      print(type(of: e))
    }
  }
}
