// PaywallLockEscape.swift
// App / ZANO / Features / Lock
//
// Spec §21's safety rule for the hard paywall: a lapsed subscription must never trap anyone.
// `EntitlementGate` releases any active lock before the paywall shows, but that release is
// best-effort (`try?`), so if a lock is somehow still running when the paywall replaces the app,
// this puts the same emergency-unlock hold the Lock tab uses above it. With no active lock it draws
// nothing.
//
// The active session comes from SwiftData (reactive, so the escape disappears the moment the lock
// ends); `SharedDefaults.activeLockSessionID` is the fallback for a mirror that is ahead of the
// store.

import SwiftUI
import SwiftData
import Core

struct PaywallLockEscape: View {
    @Query private var lockSessions: [LockSession]

    private var activeSessionID: UUID? {
        lockSessions.first(where: \.isActive)?.id ?? SharedDefaults.activeLockSessionID
    }

    var body: some View {
        if let sessionID = activeSessionID {
            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.lockStatus.paywallLockStillOn)
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                EmergencyUnlockControl(sessionID: sessionID)
            }
            .padding(Theme.Spacing.md)
            .zanoGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .background(
                Theme.Colors.background,
                in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            )
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
        }
    }
}
