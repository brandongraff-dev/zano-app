// StravaConnectView.swift
// App / ZANO / Features / Strava
//
// Settings > Strava (session 40): connect Strava so a recorded Strava workout counts toward the
// home/outdoor workout goal (docs/spec.md §3), disconnect, and see what wasn't counted (§9.8). Only reachable
// when `StravaClient.shared.isAvailable()` is true (Supabase project in the build + signed in); Settings
// hides the row otherwise, so nothing non-working is visible (App Review 2.1).
//
// Connect: the `strava-oauth` function hands back an authorize URL, `WebAuthenticationSession` (SwiftUI's
// wrapper over ASWebAuthenticationSession) opens it and catches the `zano://zano.app/strava?...` redirect,
// and the function swaps the code for tokens server-side. The app never holds a Strava token.
//
// FOUNDER TO-DO (Strava brand guidelines): replace the drawn "Connect with Strava" capsule below with
// Strava's official button artwork, and the "Powered by Strava" text with the official logo lockup
// (both from developers.strava.com/guidelines). The wording already matches.
//
// UNVERIFIED (no Mac): `WebAuthenticationSession.authenticate(using:callbackURLScheme:preferredBrowserSession:)`
// (iOS 16.4+) written from memory of the SDK; check on first CI build.

import AuthenticationServices
import SwiftUI
import Core

struct StravaConnectView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isLinked = StravaActivityStore.isLinked
    @State private var athleteName: String?
    @State private var lastFetch = StravaActivityStore.lastFetch
    @State private var enteredByHandToday = 0
    @State private var isWorking = false
    @State private var isConfirmingDisconnect = false
    @State private var message: String?

    /// Strava orange, for the stand-in connect button only (see the founder to-do above).
    private static let stravaOrange = Color(red: 252 / 255, green: 76 / 255, blue: 2 / 255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(Copy.strava.intro)
                    .zanoText(.paragraph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isLinked { connectedCard } else { connectButton }

                note(Copy.strava.howItCounts)
                if enteredByHandToday > 0 { note(Copy.strava.notCountedEnteredByHand(enteredByHandToday)) }
                note(Copy.strava.privacyNote)
                if let message { note(message) }

                Text(Copy.strava.poweredBy)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Spacing.md)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .zanoBackdrop()
        .navigationTitle(Copy.strava.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            Copy.strava.disconnectConfirmTitle,
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button(Copy.strava.disconnectConfirmButton, role: .destructive) { Task { await disconnect() } }
        } message: {
            Text(Copy.strava.disconnectConfirmMessage)
        }
    }

    // MARK: Pieces

    private var connectButton: some View {
        Button {
            Task { await connect() }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if isWorking { SwiftUI.ProgressView().tint(.white) }
                Text(Copy.strava.connectButton)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Metrics.minTapTarget)
            .background(Self.stravaOrange, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(athleteName.map(Copy.strava.connectedAs) ?? Copy.strava.connectedTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
            Text(lastFetch.map { Copy.strava.lastChecked($0.formatted(.relative(presentation: .named))) } ?? Copy.strava.neverChecked)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
            PrimaryButton(title: Copy.strava.checkNow, style: .secondary, isEnabled: !isWorking) {
                Task { await checkNow() }
            }
            PrimaryButton(title: Copy.strava.disconnect, style: .secondary, isEnabled: !isWorking) {
                isConfirmingDisconnect = true
            }
        }
        .padding(Theme.Spacing.md)
        .zanoCard()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func load() async {
        refreshLocalState()
        do {
            isLinked = try await StravaClient.shared.refreshStatus()
        } catch {
            // Offline or not configured: keep the local answer.
        }
        refreshLocalState()
    }

    private func refreshLocalState() {
        isLinked = StravaActivityStore.isLinked
        lastFetch = StravaActivityStore.lastFetch
        let today = DateInterval(start: Calendar.current.startOfDay(for: .now), end: .now)
        enteredByHandToday = StravaActivityStore.activities(in: today).filter(\.manual).count
    }

    private func connect() async {
        message = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await StravaClient.shared.authorizeURL()
            let callback = try await webAuthenticationSession.authenticate(
                using: url,
                callbackURLScheme: StravaCallback.scheme
            )
            athleteName = try await StravaClient.shared.completeAuthorization(callbackURL: callback)
            await StravaActivitySync.refreshIfDue(force: true)
            await HealthGoalChecks.run()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The person closed the sheet: nothing to say.
        } catch StravaLinkError.cancelled {
            // Tapped "Cancel" on Strava's screen.
        } catch {
            message = Self.text(for: error)
        }
        refreshLocalState()
    }

    private func checkNow() async {
        message = nil
        isWorking = true
        defer { isWorking = false }
        await StravaActivitySync.refreshIfDue(force: true)
        await HealthGoalChecks.run()
        refreshLocalState()
        if !isLinked { message = Copy.strava.errorNotLinked }
    }

    private func disconnect() async {
        message = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await StravaClient.shared.disconnect()
        } catch {
            message = Self.text(for: error)
        }
        athleteName = nil
        refreshLocalState()
    }

    private static func text(for error: Error) -> String {
        switch error as? StravaLinkError {
        case .scopeMissing?: Copy.strava.errorScopeMissing
        case .rateLimited?: Copy.strava.errorRateLimited
        case .notLinked?: Copy.strava.errorNotLinked
        default: Copy.strava.errorFailed
        }
    }
}
