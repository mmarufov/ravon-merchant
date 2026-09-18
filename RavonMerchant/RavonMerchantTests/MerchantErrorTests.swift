import XCTest
import RavonCore
@testable import RavonMerchant

/// The wording contract from `.context/STATE-REPORT.md` §4. Those strings were the app's
/// only merchant-facing error vocabulary and had to survive the move to typed mapping.
final class MerchantErrorTests: XCTestCase {

    func test_serviceErrorsMapToTheAgreedRussian() {
        let expected: [(ServiceError, String)] = [
            (.imageTooLarge,               "Фото слишком большое (макс. 5 МБ)"),
            (.unsupportedImageFormat,      "Поддерживаются только JPG, PNG, WEBP"),
            (.categoryNotEmpty,            "Сначала удалите все блюда из категории"),
            (.merchantAlreadyHasRestaurant, "У вас уже есть ресторан"),
            (.onboardingIncomplete,        "Заполните все данные перед открытием"),
            (.invalidStatusTransition,     "Невозможно изменить статус"),
        ]
        for (error, message) in expected {
            XCTAssertEqual(MerchantError.message(for: error), message)
        }
    }

    /// The report's note: "Невозможно изменить статус" is too vague for a counter. On an
    /// order action the merchant needs to know somebody else moved the order first.
    func test_invalidStatusTransitionIsWordedForTheCounterOnOrderActions() {
        XCTAssertEqual(
            MerchantError.message(for: ServiceError.invalidStatusTransition, in: .orderAction),
            "Статус заказа уже изменился — обновите список"
        )
    }

    /// The fifth message the report asked for: lock contention on
    /// `merchant_mark_order_ready` has to read as "try again", not as a scolding.
    func test_lockContentionReadsAsRetryable() {
        let expected = "Заказ уже забирает курьер — попробуйте ещё раз"
        XCTAssertEqual(MerchantError.message(for: ServiceError.orderAlreadyClaimed), expected)
        XCTAssertEqual(
            MerchantError.message(for: ServerTokenError(token: "LOCK_CONTENDED"), in: .orderAction),
            expected
        )
        XCTAssertEqual(
            MerchantError.message(for: ServerTokenError(token: "CONCURRENT_CLAIM"), in: .orderAction),
            expected
        )
    }

    func test_serverTokensAreMappedWhenTheErrorArrivesUntyped() {
        XCTAssertEqual(
            MerchantError.message(for: ServerTokenError(token: "CATEGORY_NOT_EMPTY")),
            "Сначала удалите все блюда из категории"
        )
    }

    /// An unrecognised error must never reach the screen verbatim.
    func test_unknownErrorsFallBackToRussianAndNeverLeakTheRawText() {
        struct Mystery: Error { let debugDescription = "PostgrestError(code: 42P01)" }
        let message = MerchantError.message(for: Mystery())
        XCTAssertEqual(message, "Что-то пошло не так — попробуйте ещё раз")

        let orderMessage = MerchantError.message(for: Mystery(), in: .orderAction)
        XCTAssertEqual(orderMessage, "Не удалось обновить заказ — попробуйте ещё раз")
    }

    func test_offlineIsReportedAsOfflineNotAsAGenericFailure() {
        let message = MerchantError.message(for: URLError(.notConnectedToInternet))
        XCTAssertEqual(message, "Нет соединения — проверьте интернет")
    }

    /// Every mapped message is Russian and free of Swift/SQL identifiers — the two things
    /// the old string-matching mapper let through.
    func test_everyMessageIsMerchantReadable() {
        let errors: [Error] = [
            ServiceError.notAuthenticated, ServiceError.unauthorized,
            ServiceError.orderNotFound, ServiceError.invalidResponse,
            ServiceError.cancelNotAllowed, ServiceError.insufficientStock,
            ServiceError.restaurantClosed, ServiceError.restaurantOutOfHours,
            URLError(.timedOut), ServerTokenError(token: "PGRST301"),
        ]
        for error in errors {
            for context in [MerchantError.Context.general, .orderAction] {
                let message = MerchantError.message(for: error, in: context)
                XCTAssertFalse(message.isEmpty, "\(error)")
                XCTAssertTrue(
                    message.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil,
                    "not Russian: \(message)"
                )
                for token in ["Error", "PGRST", "_", "("] {
                    XCTAssertFalse(message.contains(token),
                                   "\(message) leaks an identifier (\(token))")
                }
            }
        }
    }
}

/// Stands in for the untyped PostgREST error that carries a server `RAISE` token in its
/// description. The real type is internal to the Supabase SDK, which the merchant app does
/// not import; what matters is that the token is reachable via `String(describing:)`.
private struct ServerTokenError: Error, CustomStringConvertible {
    let token: String
    var description: String { "ServerError(message: \"\(token)\")" }
}
