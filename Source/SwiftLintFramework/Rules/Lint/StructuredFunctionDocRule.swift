import Foundation
import MarkdownKit
import Markdown
import SourceKittenFramework

public struct StructuredFunctionDocRule: ASTRule, OptInRule, ConfigurationProviderRule, AutomaticTestableRule {
    public var configuration = StructuredFunctionDocConfiguration()

    public init() {}

    public static let description = RuleDescription(
        identifier: "structured_function_doc",
        name: "Structured Function Doc",
        description:
            "Function documentation should have 1 line of summary, followed by an empty line and " +
        "detailing all parameters using markdown.",
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
        let markdown = MarkdownParser.standard.parse(lineContents)

        let document = Document(parsing: lineContents)
        print(document.debugDescription(options: .printSourceLocations))
        var visitor = MarkupExtractor()
        visitor.descendInto(document)
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

        guard case .document(var topLevelBlocks) = markdown else {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

        guard case .paragraph(let summaryText) = topLevelBlocks.removeFirst() else {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

        guard case .list(_, _, let listBlocks) = topLevelBlocks.removeFirst() else {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

        guard listBlocks.count == parameterNames.count + 1 else {
          return [
            StyleViolation(ruleDescription: Self.description,
                           severity: configuration.severityConfiguration.severity,
                           location: Location(file: file, byteOffset: docOffset))
          ]
        }

      var parameterParagraphs = [MarkdownKit.Text]()
//      listBlocks.foreach { (block: MarkdownKit.Block) in
//            guard case .listItem(_, _, let listItemBlocks) = block else {
//              return nil
//            }
//            guard case .paragraph(let text) = listItemBlocks.first else {
//              return nil
//            }
//        parameterParagraphs.append(text)
//        }


      for (parameterName, listBlock) in zip(["Parameters:"] + parameterNames, listBlocks) {
        guard case .listItem(_, _, let itemBlocks) = listBlock else {
          fatalError("zopa")
        }
        print(parameterName)
        print(listBlock)
      }

      check(blocks: topLevelBlocks)
//        for block in topLevelBlocks {
//          if case .heading(1, let text) = block {
//            outline.append(text.rawDescription)
//          }
//        }


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

    private func check(blocks: Blocks) {
      var blocks = blocks

      guard case .paragraph(let summaryText) = blocks.removeFirst() else {
        return
      }

      if summaryText.count > 1 {
        return
      }
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
}
