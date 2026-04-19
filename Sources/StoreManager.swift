import StoreKit
import SwiftUI

class StoreManager {
    static let productID = "com.frankcapria.pxf.pro"
    private var product: Product?
    private var updateTask: Task<Void, Never>?
    var onPurchaseUpdate: ((Bool) -> Void)?

    func fetchProduct() async {
        do {
            let products = try await Product.products(for: [StoreManager.productID])
            product = products.first
        } catch {

        }
    }

    func purchase() async -> Bool {
        if product == nil {
            await fetchProduct()
        }
        guard let product = product else {
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    onPurchaseUpdate?(true)
                    return true
                case .unverified(let transaction, _):
                    await transaction.finish()
                    onPurchaseUpdate?(true)
                    return true
                }
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    func checkEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.productID == StoreManager.productID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func listenForTransactions() {
        updateTask = Task {
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    if transaction.productID == StoreManager.productID {
                        let entitled = transaction.revocationDate == nil
                        onPurchaseUpdate?(entitled)
                    }
                }
            }
        }
    }

    var displayPrice: String {
        product?.displayPrice ?? "$9.99"
    }
}

@available(macOS 15.0, *)
class OfferCodeState: ObservableObject {
    @Published var isPresented: Bool = true
    var onComplete: (Bool) -> Void = { _ in }
}

@available(macOS 15.0, *)
struct OfferCodeRedemptionView: View {
    @ObservedObject var state: OfferCodeState

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .offerCodeRedemption(isPresented: $state.isPresented) { result in
                switch result {
                case .success:
                    state.onComplete(true)
                case .failure:
                    state.onComplete(false)
                @unknown default:
                    state.onComplete(false)
                }
            }
    }
}
