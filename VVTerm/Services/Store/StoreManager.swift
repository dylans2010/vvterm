import Foundation
import os.log

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    static let reviewModeCode = ReviewModeCode.value

    struct Product: Identifiable, Equatable {
        let id: String
        let displayName: String
        let displayPrice: String
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
    }

    enum RestoreState: Equatable {
        case idle
        case restoring
        case restored(hasAccess: Bool)
        case failed(String)
    }

    @Published var isPro: Bool = true
    @Published var isLifetime: Bool = true
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    @Published var restoreState: RestoreState = .idle
    @Published private(set) var isReviewModeEnabled: Bool = false
    @Published private(set) var lastPurchasedProductId: String?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "Store")

    private init() {
        logger.info("StoreKit removed; premium features unlocked")
    }

    var monthlyProduct: Product? { nil }
    var yearlyProduct: Product? { nil }
    var lifetimeProduct: Product? { nil }
    var subscriptionExpirationDate: Date? { nil }
    var isSubscriptionActive: Bool { true }
    var hasActiveSubscriptionWithLifetime: Bool { true }

    func loadProducts() async { products = [] }
    func purchase(_ product: Product) async { _ = product; purchaseState = .purchased }
    func restorePurchases() async { restoreState = .restored(hasAccess: true) }
    func checkEntitlements() async { isPro = true; isLifetime = true }

    @discardableResult
    func enableReviewMode(code: String) -> Bool {
        let ok = code.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(Self.reviewModeCode) == .orderedSame
        isReviewModeEnabled = ok
        return ok
    }

    func setReviewModeEnabled(_ enabled: Bool) {
        isReviewModeEnabled = enabled
    }
}

enum VVTermProducts {
    static let proMonthly = ""
    static let proYearly = ""
    static let proLifetime = ""
    static let subscriptionGroupId = ""
    static let allProducts: [String] = []
}

enum StoreError: LocalizedError {
    case purchaseFailed(String)
    var errorDescription: String? { "Purchasing is unavailable in this build." }
}
