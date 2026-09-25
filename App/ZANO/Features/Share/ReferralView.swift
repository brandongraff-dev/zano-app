// ReferralView.swift
// App / Features / Share
//
// docs/spec.md §4 v2 ("Referral: invite a friend → both get a streak freeze") and §13
// (`users.referral_code`, `users.referred_by`). Wave 3K.
//
// What works offline, and what doesn't:
//   - Your code: `ReferralManager.myReferralCode()` generates and saves it locally, so it shows
//     and shares with no network. (Registering it server-side is best-effort inside the manager.)
//   - Sharing: a plain-text `ShareLink` with the code. There is no invite URL or App Store link yet.
//   - Redeeming a friend's code needs the server (both freezes land in one server transaction, see
//     `ReferralBackend`). Until `ReferralManager.isBackendConfigured` is true, the field is replaced
//     by a clear "needs the network" note instead of a button that always fails.
//   - Already redeemed (`User.referredBy != nil`): says so; one per account.
//
// Entry points: Settings → Rewards → "Invite friends", and a quiet link on the unlock celebration
// (`UnlockCelebrationView`, at most every `ReferralPrompt.minimumInterval`).

import SwiftUI
import SwiftData
import UIKit
import Core

struct ReferralView: View {
    @Query private var users: [User]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Show a Done button (when presented as a sheet rather than pushed).
    var showsDoneButton = false

    @State private var code: String?
    @State private var hasBackend = false
    @State private var redeemDraft = ""
    @State private var redeemMessage: RedeemMessage?
    @State private var isRedeeming = false
    @State private var copiedTick = 0
    @State private var showsCopied = false

    struct RedeemMessage: Equatable {
        let text: String
        let isSuccess: Bool
    }

    private var alreadyRedeemed: Bool { users.first?.referredBy != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                hero
                perksCard
                redeemSection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .zanoBackdrop(glow: Theme.Colors.accent)
        .preferredColorScheme(.dark)
        .navigationTitle(Copy.share.referralScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.celebration.dismissButtonLabel) { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: copiedTick)
        .task { load() }
        .onAppear { Analytics.shared.capture(event: "referral_viewed") }
    }

    // MARK: - Hero: the code and the share button

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(Copy.share.referralHeadline)
                .zanoText(.title)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.share.referralBody)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Copy.share.referralYourCodeLabel)
                    .zanoText(.eyebrow)
                    .foregroundStyle(Theme.Colors.muted)
                if let code {
                    HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                        Text(code)
                            .font(Theme.Typography.numeral(size: 36, weight: .heavy))
                            .tracking(3)
                            .foregroundStyle(Theme.Colors.metallic)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button {
                            UIPasteboard.general.string = code
                            copiedTick += 1
                            showsCopied = true
                        } label: {
                            Label(showsCopied ? Copy.share.referralCodeCopied : Copy.share.referralCopyCodeLabel,
                                  systemImage: showsCopied ? "checkmark" : "doc.on.doc")
                                .font(Theme.Typography.captionEmphasized)
                                .foregroundStyle(Theme.Colors.text)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .frame(minHeight: Theme.Metrics.minTapTarget)
                                .background(Theme.Colors.surface2, in: Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                    }
                } else {
                    Text(Copy.share.referralCodeUnavailable)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zanoWell(radius: Theme.Radius.medium)

            if let code {
                ShareLink(
                    item: Copy.share.referralShareMessage(code: code),
                    subject: Text(Copy.share.referralShareSubject)
                ) {
                    Label(Copy.share.referralShareButton, systemImage: "square.and.arrow.up")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Metrics.primaryButtonHeight)
                        .background(Theme.Colors.accentFill, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    Analytics.shared.capture(event: "referral_share_tapped")
                })
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.large)
    }

    // MARK: - What both friends get

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.share.referralWhatYouGetTitle)
                .zanoText(.headline)
                .foregroundStyle(Theme.Colors.text)
            perkRow(Copy.share.referralPerkYou)
            perkRow(Copy.share.referralPerkFriend)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard(radius: Theme.Radius.medium)
    }

    private func perkRow(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemName: "snowflake", tint: Theme.Colors.accent, size: .small)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Redeem a friend's code

    @ViewBuilder
    private var redeemSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Copy.share.referralRedeemTitle)
                .zanoText(.headline)
                .foregroundStyle(Theme.Colors.text)

            if alreadyRedeemed {
                note(icon: "checkmark.seal", text: Copy.share.referralAlreadyRedeemed)
            } else if !hasBackend {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "wifi.slash")
                            .font(Theme.Typography.icon(.small))
                            .foregroundStyle(Theme.Colors.muted)
                            .accessibilityHidden(true)
                        Text(Copy.share.referralRedeemOfflineTitle)
                            .font(Theme.Typography.captionEmphasized)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text(Copy.share.referralRedeemOfflineMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zanoWell(radius: Theme.Radius.medium)
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField(Copy.share.referralRedeemPlaceholder, text: $redeemDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .submitLabel(.go)
                        .onSubmit { Task { await redeem() } }
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(minHeight: Theme.Metrics.minTapTarget + Theme.Spacing.xs)
                        .zanoWell(radius: Theme.Radius.small)
                    PrimaryButton(
                        title: Copy.share.referralRedeemButton,
                        style: .secondary,
                        isEnabled: !isRedeeming && !redeemDraft.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        Task { await redeem() }
                    }
                    .frame(width: 120)
                }
            }

            if let redeemMessage {
                note(icon: redeemMessage.isSuccess ? "checkmark.circle" : "exclamationmark.circle",
                     text: redeemMessage.text,
                     tint: redeemMessage.isSuccess ? Theme.Colors.accent : Theme.Colors.warning)
            }
        }
        .animation(Theme.Motion.standard(reduceMotion: reduceMotion), value: redeemMessage)
    }

    private func note(icon: String, text: String, tint: Color = Theme.Colors.muted) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(Theme.Typography.icon(.small))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func load() {
        let manager = ReferralManager.shared
        hasBackend = manager.isBackendConfigured
        code = try? manager.myReferralCode()
    }

    private func redeem() async {
        guard !isRedeeming else { return }
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            try await ReferralManager.shared.redeem(code: redeemDraft)
            redeemMessage = RedeemMessage(text: Copy.share.referralRedeemSuccess, isSuccess: true)
            redeemDraft = ""
            Analytics.shared.capture(event: "referral_redeemed")
        } catch let error as ReferralManagerError {
            let text: String
            switch error {
            case .invalidCodeFormat: text = Copy.share.referralRedeemInvalidFormat
            case .cannotRedeemOwnCode: text = Copy.share.referralRedeemOwnCode
            case .alreadyRedeemed: text = Copy.share.referralAlreadyRedeemed
            case .backendUnavailable:
                hasBackend = false
                text = Copy.share.referralRedeemOfflineTitle
            case .noSignedInUser: text = Copy.share.referralCodeUnavailable
            }
            redeemMessage = RedeemMessage(text: text, isSuccess: false)
        } catch {
            redeemMessage = RedeemMessage(text: Copy.share.referralRedeemFailed, isSuccess: false)
        }
    }
}

/// When the unlock celebration may show its quiet "Invite a friend" link: never more than once per
/// `minimumInterval`, so it stays an occasional offer, not a nag (spec §8 rule 8). Per-device
/// convenience state in standard `UserDefaults`.
enum ReferralPrompt {
    static let minimumInterval: TimeInterval = 14 * 24 * 60 * 60
    private static let lastShownKey = "zano.referralPrompt.lastShown"

    static func shouldOffer(now: Date = .now) -> Bool {
        let last = UserDefaults.standard.double(forKey: lastShownKey)
        guard last > 0 else { return true }
        return now.timeIntervalSince1970 - last >= minimumInterval
    }

    static func recordOffered(now: Date = .now) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastShownKey)
    }
}
