import Foundation
import SourceKittenFramework

public struct StructuredFunctionDocRule: ConfigurationProviderRule, AutomaticTestableRule {
  public var configuration = SeverityConfiguration(.warning)

  public init() {}

  public static let description = RuleDescription(
    identifier: "structured_function_doc",
    name: "Structured Function Doc",
    description: "A function doc should be structured.",
    kind: .lint,
    minSwiftVersion: .fourDotOne,
    nonTriggeringExamples: [
      Example("""
            /// My great property
            var myGreatProperty: String!
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

  public func validate(file: SwiftLintFile) -> [StyleViolation] {
    let docStringsTokens = file.syntaxMap.tokens.filter { token in
      return token.kind == .docComment || token.kind == .docCommentField
    }

    file.structureDictionary.traverseDepthFirst { dictionary -> [SourceKittenDictionary]? in
      print(dictionary.kind)
      print()
      return [dictionary]
    }

    let functions = file.structureDictionary.traverseDepthFirst { dictionary -> [ByteRange]? in
      guard
        dictionary.declarationKind == .functionFree,
        let offset = dictionary.offset, let length = dictionary.length
      else {
        return nil
      }

      return [ByteRange(location: offset, length: length)]
    }.sorted { $0.location < $1.location }

    let docummentedDeclsRanges = file.structureDictionary.traverseDepthFirst { dictionary -> [ByteRange]? in
      guard let docOffset = dictionary.docOffset, let docLength = dictionary.docLength else {
        return nil
      }

      return [ByteRange(location: docOffset, length: docLength)]
    }.sorted { $0.location < $1.location }

    return docStringsTokens
      .filter { token in
        guard docummentedDeclsRanges.firstIndexAssumingSorted(where: token.range.intersects) == nil,
              let contents = file.contents(for: token) else {
                return false
              }

        return contents.trimmingCharacters(in: Self.characterSet).isNotEmpty
      }.map { token in
        return StyleViolation(ruleDescription: Self.description,
                              severity: configuration.severity,
                              location: Location(file: file, byteOffset: token.offset))
      }
  }
}
