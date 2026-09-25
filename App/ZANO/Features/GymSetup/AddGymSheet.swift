// AddGymSheet.swift
// App / ZANO / Features / GymSetup
//
// spec §3 (Workout (gym): the geofence the dwell is measured in), §9.4 ("Store as geofence"),
// §24 (When In Use first). Add or edit one gym:
//
//   1. Place the pin — three ways, none of which needs location permission except the last:
//      search a gym name or address (`GymPlaceSearch`, MKLocalSearch), tap the map, or
//      "Use current location". Once placed, the pin sits at the map's centre and the person drags
//      the *map* under it to fine-tune (the standard Maps/Uber pattern; a draggable annotation
//      fights the map's own pan gesture).
//   2. Radius — 50–500 m, drawn live on the map as the geofence circle.
//   3. Name — prefilled from a search hit when empty.
//
// Save stays disabled until a pin exists (`Gym.lat`/`lng` are non-optional; there's no honest
// placeholder). MapKit-for-SwiftUI surface used — `Map(position:)`, `MapReader`/`MapProxy
// .convert(_:from:)`, `onMapCameraChange(frequency:)`, `MapCircle`, `UserAnnotation`,
// `MapStyle.standard(elevation:emphasis:pointsOfInterest:)` — is all iOS 17.0+.

import SwiftUI
@preconcurrency import CoreLocation
@preconcurrency import MapKit
import Core

/// The editable values of a gym, independent of SwiftData.
struct GymDraft: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Int
}

struct AddGymSheet: View {
    /// `nil` to add; a draft of the existing gym to edit.
    let existing: GymDraft?
    let onSave: (GymDraft) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var radius: Double
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion?

    @State private var query = ""
    @State private var search = GymPlaceSearch()
    @FocusState private var isSearchFocused: Bool

    private var authorization: GymLocationAuthorization { .shared }
    // Created on first tap (a `@State` default would build a `CLLocationManager` on every re-init).
    @State private var fetcher: GymOneShotLocationFetcher?
    @State private var isLocating = false
    @State private var locationErrorMessage: String?
    @State private var placedTick = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(existing: GymDraft? = nil, onSave: @escaping (GymDraft) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: existing?.name ?? "")
        let radius = Double(existing?.radiusMeters ?? GymVerificationDefaults.defaultRadiusMeters)
        _radius = State(initialValue: radius)
        if let existing {
            let center = CLLocationCoordinate2D(latitude: existing.latitude, longitude: existing.longitude)
            _coordinate = State(initialValue: center)
            _position = State(initialValue: .region(Self.region(center: center, radiusMeters: radius)))
        } else {
            _coordinate = State(initialValue: nil)
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    private var radiusRange: ClosedRange<Double> {
        Double(GymVerificationDefaults.minimumRadiusMeters)...Double(GymVerificationDefaults.maximumRadiusMeters)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    searchBlock
                    mapBlock
                    locationBlock
                    radiusBlock
                    nameBlock
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .zanoBackdrop()
            .navigationTitle(existing == nil ? Copy.gym.addSheetTitle : Copy.gym.editSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.common.save) {
                        guard let coordinate else { return }
                        onSave(GymDraft(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            radiusMeters: Int(radius)
                        ))
                    }
                    .fontWeight(.semibold)
                    .disabled(coordinate == nil)
                }
            }
        }
        // A sheet is its own presentation: set scheme + tint explicitly.
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .sensoryFeedback(.success, trigger: placedTick)
        .sensoryFeedback(.selection, trigger: Int(radius))
        .task(id: query) {
            // Debounce: a superseded query cancels this task during the sleep.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search.search(query, near: visibleRegion)
        }
    }

    // MARK: Search

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Typography.icon(.medium))
                    .foregroundStyle(Theme.Colors.muted)
                    .accessibilityHidden(true)
                TextField(
                    text: $query,
                    prompt: Text(Copy.gym.searchPlaceholder).foregroundStyle(Theme.Colors.muted)
                ) {
                    Text(Copy.gym.searchPlaceholder)
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                if search.isSearching {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Colors.muted)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        search.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.Typography.icon(.medium))
                            .foregroundStyle(Theme.Colors.muted)
                            .minTapTarget()
                    }
                    .accessibilityLabel(Copy.common.cancel)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.Metrics.primaryButtonHeight)
            .zanoGlass()

            searchResults
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.results.isEmpty, !trimmed.isEmpty {
            VStack(spacing: 0) {
                ForEach(search.results) { result in
                    Button {
                        select(result)
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            IconBadge(systemName: "mappin", tint: Theme.Colors.accent, size: .small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.text)
                                    .lineLimit(1)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.muted)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if result.id != search.results.last?.id {
                        Rectangle()
                            .fill(Theme.Colors.hairline)
                            .frame(height: 1)
                            .padding(.leading, Theme.Spacing.md + Theme.Metrics.iconBadgeSmall + Theme.Spacing.sm)
                    }
                }
            }
            .zanoCard()
        } else if search.didFail, search.answeredQuery == trimmed, !trimmed.isEmpty {
            searchNote(Copy.gym.searchFailed)
        } else if search.answeredQuery == trimmed, !trimmed.isEmpty, !search.isSearching {
            searchNote(Copy.gym.searchNoResults)
        }
    }

    private func searchNote(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.muted)
            .padding(.horizontal, Theme.Spacing.xs)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func select(_ result: GymPlaceResult) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = result.name
        }
        query = ""
        search.clear()
        isSearchFocused = false
        place(result.coordinate)
    }

    // MARK: Map

    private var mapBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            MapReader { proxy in
                Map(position: $position) {
                    if let coordinate {
                        MapCircle(center: coordinate, radius: radius)
                            .foregroundStyle(Theme.Colors.accent.opacity(0.18))
                            .stroke(Theme.Colors.accent, lineWidth: 2)
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .including([.fitnessCenter])))
                .onTapGesture { point in
                    if let tapped = proxy.convert(point, from: .local) {
                        place(tapped)
                    }
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    visibleRegion = context.region
                    // Once placed, the pin is the map's centre: dragging the map moves it.
                    if coordinate != nil {
                        coordinate = context.region.center
                    }
                }
            }
            .overlay {
                if coordinate != nil {
                    GymMapPin()
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Copy.gym.mapAccessibilityLabel)

            Text(coordinate == nil ? Copy.gym.mapHintUnplaced : Copy.gym.mapHintPlaced)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Drops the pin at `target` and centres the camera on it, zoomed so the circle fits.
    private func place(_ target: CLLocationCoordinate2D) {
        coordinate = target
        locationErrorMessage = nil
        placedTick += 1
        withAnimation(reduceMotion ? nil : Theme.Motion.springStandard) {
            position = .region(Self.region(center: target, radiusMeters: radius))
        }
    }

    private static func region(center: CLLocationCoordinate2D, radiusMeters: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, latitudinalMeters: radiusMeters * 4, longitudinalMeters: radiusMeters * 4)
    }

    // MARK: Current location (When In Use primer first — spec §24)

    @ViewBuilder
    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if authorization.level == .notDetermined {
                LocationPermissionPrimer(kind: .whenInUse, authorization: authorization)
            } else if authorization.level != .denied {
                locateButton
            }

            if let locationErrorMessage {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.icon(.xsmall))
                        .accessibilityHidden(true)
                    Text(locationErrorMessage)
                        .font(Theme.Typography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.Colors.danger)
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
        .onChange(of: authorization.level) { oldLevel, newLevel in
            // Just granted from the primer: finish the job the person asked for.
            if oldLevel == .notDetermined, newLevel == .whenInUse || newLevel == .always, coordinate == nil {
                Task { await locate() }
            }
        }
    }

    @ViewBuilder
    private var locateButton: some View {
        if isLocating {
            HStack(spacing: Theme.Spacing.xs) {
                SwiftUI.ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Colors.muted)
                Text(Copy.gym.locatingLabel)
            }
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.muted)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.primaryButtonHeight)
            .accessibilityElement(children: .combine)
        } else {
            // Secondary once a pin exists (the map confirms it); primary while nothing is placed.
            PrimaryButton(
                title: Copy.gym.locateButtonLabel,
                systemImage: "location.fill",
                style: coordinate == nil ? .standard : .secondary
            ) {
                Task { await locate() }
            }
        }
    }

    private func locate() async {
        isLocating = true
        locationErrorMessage = nil
        defer { isLocating = false }
        let activeFetcher = fetcher ?? GymOneShotLocationFetcher()
        fetcher = activeFetcher
        do {
            place(try await activeFetcher.fetch())
        } catch {
            locationErrorMessage = Copy.gym.locationFailedMessage
        }
    }

    // MARK: Radius

    private var radiusBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.gym.radiusLabel(meters: Int(radius)))
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)
                .monospacedDigit()
            Slider(value: $radius, in: radiusRange, step: 10) {
                Text(Copy.gym.radiusLabel(meters: Int(radius)))
            }
            .tint(Theme.Colors.accent)
            Text(Copy.gym.radiusHint)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zanoCard()
    }

    // MARK: Name

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Copy.gym.nameFieldLabel)
                .zanoText(.eyebrow)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, Theme.Spacing.xs)
            TextField(
                text: $name,
                prompt: Text(Copy.gym.nameFieldPlaceholder).foregroundStyle(Theme.Colors.muted)
            ) {
                Text(Copy.gym.nameFieldLabel)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.text)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.Metrics.primaryButtonHeight)
            .zanoCard(radius: Theme.Radius.small)
        }
    }
}

/// The centre pin: a ZANO-blue disc with a dumbbell, on a short stem whose tip marks the exact
/// point (the stem's bottom sits on the map's centre).
private struct GymMapPin: View {
    private let disc: CGFloat = 34
    private let stem: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accentFill)
                    .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 8)
                Circle()
                    .strokeBorder(Theme.Colors.onAccent.opacity(0.9), lineWidth: 2)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.onAccent)
            }
            .frame(width: disc, height: disc)
            Rectangle()
                .fill(Theme.Colors.onAccent)
                .frame(width: 2, height: stem)
        }
        .offset(y: -(disc + stem) / 2)
        .accessibilityHidden(true)
    }
}
