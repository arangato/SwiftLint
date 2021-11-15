import Foundation
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
        nonTriggeringExamples: [
            Example("""
            /// My great function.
            func myGreatProperty: String!
            """),
            Example("""
            //////////////////////////////////////
            //
            // Copyright header.
            //
            //////////////////////////////////////
            """),
            Example("""
            /// Look here for more info: https://github.com.
            var myGreatProperty: String!
            """),
            Example("""
            /// Look here for more info:
            /// https://github.com.
            var myGreatProperty: String!
            """)
        ],
        triggeringExamples: [
            Example("""
            ↓/// My great property
            // Not a doc string
            var myGreatProperty: String!
            """),
            Example("""
            ↓/// Look here for more info: https://github.com.
            // Not a doc string
            var myGreatProperty: String!
            """)
        ]
    )

    private static let characterSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/"))

    private static let missingParametersHeader = "missing '- Parameters:' markdown header"

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

        guard let summary = extractSummary(in: docLines), summary.count <= configuration.maxSummaryLineCount else {
            return [
                StyleViolation(ruleDescription: Self.description,
                               severity: configuration.severityConfiguration.severity,
                               location: Location(file: file, byteOffset: docOffset))
            ]
        }

        return []
    }

    func extractSummary(in lines: [Line]) -> [Line]? {
        var summary = [Line]()
        for line in lines {
            if line.content.trimmingCharacters(in: Self.characterSet).isEmpty {
                return summary
            }
            summary.append(line)
        }
        return nil
    }
}
