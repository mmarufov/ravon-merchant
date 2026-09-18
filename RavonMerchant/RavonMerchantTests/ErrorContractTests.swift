import XCTest
@testable import RavonMerchant

/// The repo standard is that contracts are enforced by something other than memory.
///
/// This is that enforcement for error handling. The app had three near-duplicate `mapError`
/// helpers and 31 of 50 catch blocks assigning `error.localizedDescription` — raw Supabase
/// text in a Russian UI — and one view model (`OrdersViewModel`) whose `errorMessage` was
/// never rendered by any view at all, so the four most important mutations in the app
/// failed in total silence. Both failure modes are cheap to reintroduce and invisible in
/// review, so they are checked here instead.
///
/// The source tree is located from `#filePath`, which the compiler bakes in, so the checks
/// run against the checkout the test binary was built from.
final class ErrorContractTests: XCTestCase {

    // MARK: - Source locations

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)          // …/RavonMerchantTests/ErrorContractTests.swift
            .deletingLastPathComponent()          // …/RavonMerchantTests
            .deletingLastPathComponent()          // …/RavonMerchant (container)
            .appendingPathComponent("RavonMerchant")
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func source(_ url: URL) throws -> [(line: Int, text: String)] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.components(separatedBy: .newlines).enumerated().map { ($0.offset + 1, $0.element) }
    }

    func test_sourceTreeIsWhereWeThinkItIs() throws {
        let viewModels = Self.appSources.appendingPathComponent("ViewModels")
        XCTAssertFalse(try swiftFiles(under: viewModels).isEmpty,
                       "the contract checks below cannot see the source at \(viewModels.path)")
    }

    // MARK: - Rule 1: no raw error text on a user-facing path

    /// A view model may never put `error.localizedDescription` (or `errorDescription`, or a
    /// `String(describing:)` of an error) into something a merchant reads. Everything goes
    /// through `MerchantError.message(for:in:)`, which maps known errors to Russian and
    /// logs the rest.
    func test_noViewModelRendersRawErrorText() throws {
        let banned = ["localizedDescription", "errorDescription"]
        var offences: [String] = []

        for file in try swiftFiles(under: Self.appSources.appendingPathComponent("ViewModels")) {
            for (line, text) in try source(file) where !isComment(text) {
                for token in banned where text.contains(token) {
                    offences.append("\(file.lastPathComponent):\(line): \(text.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(offences.isEmpty, """
            A view model is putting raw error text on screen. Route it through \
            MerchantError.message(for:in:) instead — see Support/MerchantError.swift.
            \(offences.joined(separator: "\n"))
            """)
    }

    /// Same rule for the views: no view should be formatting an error itself either.
    func test_noViewRendersRawErrorText() throws {
        var offences: [String] = []
        for file in try swiftFiles(under: Self.appSources.appendingPathComponent("Views")) {
            for (line, text) in try source(file) where !isComment(text) {
                if text.contains("localizedDescription") {
                    offences.append("\(file.lastPathComponent):\(line)")
                }
            }
        }
        XCTAssertTrue(offences.isEmpty, "views must not render raw error text: \(offences)")
    }

    /// The string-matching `mapError` helpers are gone; they must not come back. They
    /// matched Swift case names against `localizedDescription`, which for a
    /// `LocalizedError` is the localised text — so every branch was dead code that fell
    /// through to the raw description.
    func test_noPrivateMapErrorHelpersRemain() throws {
        var offences: [String] = []
        for file in try swiftFiles(under: Self.appSources) {
            for (line, text) in try source(file) where !isComment(text) {
                if text.contains("func mapError(") {
                    offences.append("\(file.lastPathComponent):\(line)")
                }
            }
        }
        XCTAssertTrue(offences.isEmpty,
                      "per-view-model mapError helpers are consolidated into MerchantError: \(offences)")
    }

    // MARK: - Rule 2: every error a view model publishes is actually rendered

    /// Each `@Published` error property on a view model must be read by at least one view.
    /// `OrdersViewModel.errorMessage` satisfied every type check and was still dead: no
    /// view referenced it, so every failed accept/reject/cancel was swallowed.
    func test_everyPublishedErrorPropertyIsRenderedBySomeView() throws {
        let viewSources = try swiftFiles(under: Self.appSources.appendingPathComponent("Views"))
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        var unrendered: [String] = []
        for file in try swiftFiles(under: Self.appSources.appendingPathComponent("ViewModels")) {
            for (_, text) in try source(file) {
                guard let property = publishedErrorProperty(in: text) else { continue }
                if !viewSources.contains(property) {
                    unrendered.append("\(file.lastPathComponent).\(property)")
                }
            }
        }

        XCTAssertTrue(unrendered.isEmpty, """
            These view models publish an error nothing renders, so the failure is invisible \
            at runtime. Bind it with `.errorAlert(...)` or an `ErrorBanner`.
            \(unrendered.joined(separator: "\n"))
            """)
    }

    // MARK: - Parsing helpers

    private func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*")
    }

    /// `@Published var somethingError: String?` → "somethingError".
    private func publishedErrorProperty(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@Published"), trimmed.contains("String?") else { return nil }
        guard let varRange = trimmed.range(of: "var ") else { return nil }
        let rest = trimmed[varRange.upperBound...]
        let name = String(rest.prefix(while: { $0 != ":" && $0 != " " }))
        return name.lowercased().contains("error") ? name : nil
    }
}
