import Foundation
import RavonCore

/// The one place an error becomes something a merchant can read.
///
/// Before this existed the app had three near-identical `mapError` helpers that matched
/// substrings — `desc.contains("imageTooLarge")` — against `error.localizedDescription`.
/// For a `LocalizedError` such as `ServiceError` that description is *already* the Russian
/// `errorDescription`, so none of those branches could ever fire: every one of them fell
/// through to `return desc`. Together with the 31 catch blocks that assigned
/// `error.localizedDescription` outright, the practical result was raw Supabase text in a
/// Russian UI.
///
/// The rule: a user-facing error path never renders `error.localizedDescription`. Known
/// errors are switched over by type; anything unrecognised gets a generic Russian sentence
/// and the underlying text goes to the log instead of the screen.
/// `ErrorContractTests` fails the test run if a view model breaks that rule.
enum MerchantError {

    /// Which screen the failure happened on. Only used where the same underlying error
    /// needs different wording — `invalidStatusTransition` on an order is a different
    /// event for the merchant than on the restaurant lifecycle.
    enum Context {
        case general
        /// Accept / reject / start-preparing / mark-ready / cancel.
        case orderAction
    }

    nonisolated static func message(for error: Error, in context: Context = .general) -> String {
        if let service = error as? ServiceError {
            return message(for: service, in: context)
        }
        if let auth = error as? AuthError {
            return auth.errorDescription ?? fallback(for: context)
        }
        if let offline = offlineMessage(for: error) {
            return offline
        }
        // Server-side `RAISE EXCEPTION` codes arrive as an untyped PostgREST error whose
        // message carries the SQL token. Matching those is still string matching, but on a
        // documented server contract rather than on a Swift case name.
        if let mapped = serverCodeMessage(for: error, in: context) {
            return mapped
        }
        log(error)
        return fallback(for: context)
    }

    // MARK: - Typed

    nonisolated private static func message(for error: ServiceError, in context: Context) -> String {
        switch error {
        case .invalidStatusTransition:
            // "Невозможно изменить статус" (the old Settings wording) is too vague for a
            // counter. What actually happened is that someone else moved the order first.
            return context == .orderAction
                ? "Статус заказа уже изменился — обновите список"
                : "Невозможно изменить статус"
        case .orderAlreadyClaimed, .orderNoLongerPickupable:
            return "Заказ уже забирает курьер — попробуйте ещё раз"
        case .orderNotFound:
            return "Заказ не найден — возможно, он отменён"
        case .cancelNotAllowed, .cancelAfterPickupNotAllowed, .cannotCancelPostPickup:
            return "Отмена невозможна — заказ уже забран курьером"
        case .notAuthenticated:
            return "Сессия истекла — войдите снова"
        case .unauthorized:
            return "Недостаточно прав для этого действия"
        case .imageTooLarge:
            return "Фото слишком большое (макс. 5 МБ)"
        case .unsupportedImageFormat:
            return "Поддерживаются только JPG, PNG, WEBP"
        case .categoryNotEmpty:
            return "Сначала удалите все блюда из категории"
        case .merchantAlreadyHasRestaurant:
            return "У вас уже есть ресторан"
        case .onboardingIncomplete:
            return "Заполните все данные перед открытием"
        case .insufficientStock:
            return "Недостаточно товара на складе"
        case .restaurantClosed, .restaurantNotAccepting, .restaurantOutOfHours,
             .restaurantOverloaded:
            // These are already merchant-readable Russian in core.
            return error.errorDescription ?? fallback(for: context)
        case .invalidResponse:
            return "Сервер ответил неожиданно — попробуйте ещё раз"
        default:
            // Courier- and consumer-only cases. Core's Russian text is fine where it
            // exists; the fallback covers anything added to `ServiceError` later.
            return error.errorDescription ?? fallback(for: context)
        }
    }

    // MARK: - Untyped

    /// SQL tokens raised by the order/menu RPCs, mapped to merchant-facing Russian. Keys
    /// are matched case-insensitively against the error text.
    nonisolated private static let serverCodes: [(token: String, message: String)] = [
        ("LOCK_CONTENDED",                "Заказ уже забирает курьер — попробуйте ещё раз"),
        ("CONCURRENT_CLAIM",              "Заказ уже забирает курьер — попробуйте ещё раз"),
        ("ORDER_ALREADY_CLAIMED",         "Заказ уже забирает курьер — попробуйте ещё раз"),
        ("ORDER_NO_LONGER_PICKUPABLE",    "Заказ больше недоступен"),
        ("INVALID_STATUS_TRANSITION",     "Статус заказа уже изменился — обновите список"),
        ("ORDER_NOT_FOUND",               "Заказ не найден — возможно, он отменён"),
        ("CANCEL_NOT_ALLOWED",            "Отмена невозможна — заказ уже забран курьером"),
        ("MERCHANT_ALREADY_HAS_RESTAURANT", "У вас уже есть ресторан"),
        ("ONBOARDING_INCOMPLETE",         "Заполните все данные перед открытием"),
        ("CATEGORY_NOT_EMPTY",            "Сначала удалите все блюда из категории"),
        ("IMAGE_TOO_LARGE",               "Фото слишком большое (макс. 5 МБ)"),
        ("UNSUPPORTED_IMAGE_FORMAT",      "Поддерживаются только JPG, PNG, WEBP"),
        ("RESTAURANT_CLOSED",             "Ресторан закрыт"),
        ("RESTAURANT_NOT_ACCEPTING",      "Ресторан не принимает заказы"),
        ("INSUFFICIENT_STOCK",            "Недостаточно товара на складе"),
        ("UNAUTHORIZED",                  "Недостаточно прав для этого действия"),
        // PostgREST's RLS refusal. The merchant cannot fix it, but "нет прав" is at least
        // true, and it is the signature of calling an RPC that is not ours — which is
        // exactly what "Отменить заказ" used to do.
        ("PGRST301",                      "Недостаточно прав для этого действия"),
        ("42501",                         "Недостаточно прав для этого действия"),
    ]

    nonisolated private static func serverCodeMessage(for error: Error, in context: Context) -> String? {
        let haystack = String(describing: error).uppercased()
        for entry in serverCodes where haystack.contains(entry.token) {
            return entry.message
        }
        return nil
    }

    nonisolated private static func offlineMessage(for error: Error) -> String? {
        guard let url = error as? URLError else { return nil }
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "Нет соединения — проверьте интернет"
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Сервер не отвечает — проверьте соединение и попробуйте ещё раз"
        default:
            return nil
        }
    }

    nonisolated private static func fallback(for context: Context) -> String {
        switch context {
        case .orderAction:
            return "Не удалось обновить заказ — попробуйте ещё раз"
        case .general:
            return "Что-то пошло не так — попробуйте ещё раз"
        }
    }

    /// The raw text still has to go somewhere, or a real bug becomes undiagnosable.
    /// Console, not the counter screen.
    nonisolated private static func log(_ error: Error) {
        #if DEBUG
        print("[MerchantError] unmapped: \(String(reflecting: error))")
        #endif
    }
}

// MARK: - Backend gaps

/// Actions the UI offers that the server cannot currently perform.
///
/// Derived from `OrderLifecycle`, which lists `merchant_cancel_order` as a transition with
/// no implementing RPC. Reading the gap out of the lifecycle model rather than hardcoding
/// a `false` here means the button re-enables itself the moment core ships the RPC.
enum MerchantBackendGap {

    /// `merchant_cancel_order` does not exist yet. Until it does, merchant cancel has no
    /// server path — the app used to call `cancel_order_by_consumer`, the *consumer's* RPC,
    /// which rejects a merchant caller and failed silently.
    nonisolated static var merchantCancelAvailable: Bool {
        !OrderLifecycle.unimplementedRPCs.contains("merchant_cancel_order")
    }

    nonisolated static let merchantCancelUnavailableMessage =
        "Отмена заказа рестораном пока недоступна — свяжитесь с поддержкой"
}
