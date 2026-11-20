import MiraNoteKit
import StoreKit
import SwiftUI
import UIKit

/// MiraNote Plus (api #95 step 4): the plans with what Guideline 3.1.2
/// asks a subscription screen to say -- price and period, the
/// introductory offer and the price after it, automatic renewal, Terms
/// and Privacy links -- and Restore. Shown when a free allowance runs out
/// and from Settings; closing it changes nothing.
struct PaywallSheet: View {
    var plus: PlusStore
    /// Opened by a used-up free allowance rather than from Settings.
    var limitReached: Bool
    var onClose: () -> Void

    @State private var selected = PlusStore.ProductID.yearly
    @State private var introEligible = false
    @State private var loadFailed = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("paywall.close")
            }
            .padding(.top, 8)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 8) {
                        benefit("More AI pictures and backgrounds every month")
                        benefit("A photo memory every day")
                        benefit("Many more chats and rewrites with Mira every day")
                    }
                    plans
                    if let message {
                        Text(message)
                            .font(Sans.font(size: 14, weight: 600))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("paywall.message")
                    }
                    disclosure
                }
                .padding(.bottom, 16)
            }
            VStack(spacing: 10) {
                Button(action: subscribe) {
                    Text("Subscribe").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryPill())
                .disabled(busy || product(selected) == nil)
                .accessibilityIdentifier("paywall.subscribe")
                Button(action: restore) {
                    Text("Restore Purchases").frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftPill())
                .disabled(busy)
                .accessibilityIdentifier("paywall.restore")
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, SettingsStyle.inset)
        .background(Palette.paper.ignoresSafeArea())
        .task { await load() }
    }

    @ViewBuilder private var header: some View {
        Text(limitReached ? "You've reached the free limit" : "MiraNote Plus")
            .font(Sans.font(size: 26, weight: 600))
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("paywall.title")
        Text(limitReached ? "MiraNote Plus gives you more of Mira's AI." : "More of Mira's AI, every day.")
            .font(Sans.font(size: 15, weight: 500))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func benefit(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.forest)
                // Decoration: VoiceOver reads the benefit, not "checkmark".
                .accessibilityHidden(true)
            Text(text)
                .font(Sans.font(size: 15, weight: 500))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var plans: some View {
        if plus.products.isEmpty {
            if loadFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The plans could not load. Check your connection and try again.")
                        .font(Sans.font(size: 14, weight: 500))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await load() } }
                        .font(Sans.font(size: 15, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("paywall.retry")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(plus.products, id: \.id) { product in
                    planCard(product)
                }
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let chosen = product.id == selected
        return Button { selected = product.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.id == PlusStore.ProductID.yearly ? "Yearly" : "Monthly")
                    .font(Sans.font(size: 16, weight: 700))
                    .foregroundStyle(Palette.ink)
                if let period = product.subscription?.subscriptionPeriod {
                    Text(Self.price(product.displayPrice, per: period))
                        .font(Sans.font(size: 15, weight: 600))
                        .foregroundStyle(Palette.ink)
                }
                if let intro = introLine(product) {
                    Text(intro)
                        .font(Sans.font(size: 13, weight: 500))
                        .foregroundStyle(SettingsStyle.value)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.warmWhite))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(chosen ? Palette.ink : Palette.hairline, lineWidth: chosen ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("paywall.plan.\(product.id)")
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("""
            Payment is charged to your Apple Account when you confirm. Plus renews automatically at the \
            regular price shown above unless you cancel at least 24 hours before the current period ends. \
            Manage or cancel it in your Apple Account settings.
            """)
                .font(Sans.font(size: 12, weight: 500))
                .lineSpacing(AIDataLines.spacing(for: 12))
                .foregroundStyle(SettingsStyle.value)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.disclosure")
            HStack(spacing: 18) {
                Link("Terms of Use", destination: MiraNoteConfig.Legal.terms)
                    .accessibilityIdentifier("paywall.terms")
                Link("Privacy Policy", destination: MiraNoteConfig.Legal.privacy)
                    .accessibilityIdentifier("paywall.privacy")
            }
            .font(Sans.font(size: 13, weight: 600))
            .foregroundStyle(Palette.ink)
        }
    }

    /// The introductory offer and the regular price after it, for a writer
    /// who can still take it.
    private func introLine(_ product: Product) -> String? {
        guard introEligible, let subscription = product.subscription,
              let offer = subscription.introductoryOffer else { return nil }
        let length = Self.length(offer.period, times: offer.periodCount)
        let regular = Self.price(product.displayPrice, per: subscription.subscriptionPeriod)
        switch offer.paymentMode {
        case .freeTrial:
            return String(appCopy: "Introductory offer: free for \(length), then \(regular).")
        case .payAsYouGo:
            let each = Self.price(offer.displayPrice, per: offer.period)
            return String(appCopy: "Introductory offer: \(each) for \(length), then \(regular).")
        default:
            return String(appCopy: "Introductory offer: \(offer.displayPrice) for \(length), then \(regular).")
        }
    }

    static func price(_ price: String, per period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .year: return String(appCopy: "\(price) a year")
        case .month: return String(appCopy: "\(price) a month")
        case .week: return String(appCopy: "\(price) a week")
        default: return String(appCopy: "\(price) a day")
        }
    }

    static func length(_ period: Product.SubscriptionPeriod, times count: Int) -> String {
        let value = period.value * count
        switch period.unit {
        case .year: return String(appCopy: "\(value) years")
        case .month: return String(appCopy: "\(value) months")
        case .week: return String(appCopy: "\(value) weeks")
        default: return String(appCopy: "\(value) days")
        }
    }

    private func product(_ id: String) -> Product? {
        plus.products.first { $0.id == id }
    }

    private func load() async {
        loadFailed = false
        do {
            if plus.products.isEmpty { try await plus.loadProducts() }
            loadFailed = plus.products.isEmpty
            introEligible = await plus.products.first?.subscription?.isEligibleForIntroOffer ?? false
        } catch {
            loadFailed = true
        }
    }

    private func subscribe() {
        guard !busy, let product = product(selected) else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                switch try await plus.purchase(product) {
                case .purchased: onClose()
                case .pending: message = String(appCopy: "Your purchase is waiting for approval.")
                case .cancelled: break
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func restore() {
        guard !busy else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                if try await plus.restore() {
                    onClose()
                } else {
                    message = String(appCopy: "No Plus subscription was found for this Apple Account.")
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Shows `PaywallSheet` over whatever is on screen, like
/// `SignInPresenter`; one at a time. A swipe closes it too.
@MainActor
enum PaywallPresenter {
    private static weak var shown: UIViewController?

    /// In a build that offers sign-in (`Account.isOffered`): a free
    /// allowance used up by an action the writer started opens the paywall
    /// (after a sync and one more try when the phone has Plus), and Plus
    /// starts following the App Store.
    static func install(_ plus: PlusStore, consent: AIConsent) {
        guard Account.isOffered else { return }
        consent.syncPlus = { await plus.syncIfPlus() }
        consent.limitReached = { _ in show(plus, limitReached: true) }
        plus.start()
    }

    static func show(_ plus: PlusStore, limitReached: Bool) {
        guard shown == nil, let top = AIConsentPresenter.topController() else { return }
        let sheet = PaywallSheet(plus: plus, limitReached: limitReached) { shown?.dismiss(animated: true) }
            .environment(\.locale, AppSettings.shared.language.locale)
        let host = UIHostingController(rootView: sheet)
        host.view.backgroundColor = UIColor(Palette.paper)
        host.modalPresentationStyle = .pageSheet
        host.sheetPresentationController?.detents = [.large()]
        shown = host
        top.present(host, animated: true)
    }
}

extension PlusStore {
    /// The app's one store. UI tests send the server sync to a stand-in.
    static let shared: PlusStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            return PlusStore(account: .shared, subscriptions: UITestSubscriptions())
        }
        #endif
        return PlusStore(account: .shared, subscriptions: LiveSubscriptionsAPI())
    }()
}
