// ScreenTimeSummaryView.swift
// Core / UI / Components
//
// Today's screen time, the way Opal's home does it (the reference the founder picked, 2026-09-24):
// one big total, a three-stat row, an hourly bar chart, and the day's top apps. ZANO's twist is
// the split that matters to it: time spent in *locked* apps is red on the chart and in the list,
// everything else is quiet.
//
// Where it runs (spec §5.15, §27): screen-time numbers can only be read inside a
// DeviceActivityReport extension, so the real data path is `ZANOReport` building a
// `ScreenTimeSummary` and rendering this view; Today embeds that extension with
// `DeviceActivityReport(.zanoToday, filter:)`. The view itself is plain SwiftUI with no data access,
// so the app can also draw it from demo data for CI screenshots (the Simulator has no Screen Time
// data at all). App icons come from FamilyControls' own `Label(token)`, drawn in the extension.

import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

extension DeviceActivityReport.Context {
    /// Today's screen-time summary (`ZANOReport`'s `TodayScreenTimeReport`).
    /// Computed, not a stored `static let`: a stored static of a type that may not be `Sendable`
    /// is an error under Swift 6 strict concurrency (Core's mode).
    public static var zanoToday: DeviceActivityReport.Context { .init(rawValue: "ZANOToday") }
    /// The charged ZANO star on Today's hero (`ZANOReport`'s `ChargeMarkReport`).
    public static var zanoMark: DeviceActivityReport.Context { .init(rawValue: "ZANOMark") }
}

/// Everything the view shows, computed on device.
public struct ScreenTimeSummary: Equatable {
    public struct AppUsage: Identifiable, Equatable {
        public let id: String
        public let name: String
        /// Nil in demo data; the extension always has one.
        public let token: ApplicationToken?
        public let duration: TimeInterval
        public let isLocked: Bool

        public init(id: String, name: String, token: ApplicationToken? = nil, duration: TimeInterval, isLocked: Bool) {
            self.id = id
            self.name = name
            self.token = token
            self.duration = duration
            self.isLocked = isLocked
        }
    }

    /// Minutes used in one clock hour, split into locked-app time and everything else.
    public struct Hour: Identifiable, Equatable {
        public let id: Int
        public let lockedMinutes: Double
        public let otherMinutes: Double

        public init(hour: Int, lockedMinutes: Double, otherMinutes: Double) {
            self.id = hour
            self.lockedMinutes = lockedMinutes
            self.otherMinutes = otherMinutes
        }
    }

    public let total: TimeInterval
    public let lockedTime: TimeInterval
    public let pickups: Int
    /// Most used first.
    public let apps: [AppUsage]
    /// Any subset of 0...23; missing hours read as zero.
    public let hours: [Hour]
    /// "Now", for how much of the day has passed (time offline) and which hours are still ahead.
    public let asOf: Date

    public init(total: TimeInterval, lockedTime: TimeInterval, pickups: Int, apps: [AppUsage], hours: [Hour], asOf: Date = .now) {
        self.total = total
        self.lockedTime = lockedTime
        self.pickups = pickups
        self.apps = apps
        self.hours = hours
        self.asOf = asOf
    }

    /// The waking day starts here for the star's charge: sleep isn't "time off your phone".
    public static let wakingDayStartHour = 6

    /// 0...1: the share of today's waking hours (from 6 AM to `asOf`) not spent on the phone. Time
    /// in locked apps counts double: the star should dim fastest on the apps you chose to lock.
    /// Before 6 AM the waking day hasn't started, so the star is full.
    public var charge: Double {
        let calendar = Calendar.current
        guard let start = calendar.date(bySettingHour: Self.wakingDayStartHour, minute: 0, second: 0, of: asOf) else { return 0 }
        let elapsed = asOf.timeIntervalSince(start)
        guard elapsed > 0 else { return 1 }
        let used = total + lockedTime
        return min(1, max(0, 1 - used / elapsed))
    }
}

public struct ScreenTimeSummaryView: View {
    private let summary: ScreenTimeSummary

    /// The chart covers the waking day, like the reference (6 AM to 10 PM).
    private static let chartHours = Array(6...22)
    private static let axisHours: Set<Int> = [6, 10, 14, 18, 22]
    private static let chartHeight: CGFloat = 120
    private static let listLimit = 5

    public init(summary: ScreenTimeSummary) {
        self.summary = summary
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            totalBlock
            statsRow
            chart
            list
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Total

    private var totalBlock: some View {
        VStack(spacing: 2) {
            Text(Copy.screenTime.duration(summary.total))
                .font(.system(size: 64, weight: .heavy).width(.compressed))
                .foregroundStyle(Theme.Colors.text)
                .monospacedDigit()
            Text(Copy.screenTime.totalLabel)
                .font(Theme.Typography.captionEmphasized)
                .foregroundStyle(Theme.Colors.muted)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            stat(Copy.screenTime.mostUsed) {
                HStack(spacing: -6) {
                    ForEach(summary.apps.prefix(3)) { app in
                        ScreenTimeAppIcon(app: app, size: 24)
                    }
                }
            }
            stat(Copy.screenTime.lockedApps) {
                Text(Copy.screenTime.duration(summary.lockedTime))
                    .font(.system(size: 22, weight: .bold).width(.condensed))
                    .foregroundStyle(summary.lockedTime > 0 ? Theme.Colors.danger : Theme.Colors.text)
            }
            stat(Copy.screenTime.pickups) {
                Text("\(summary.pickups)")
                    .font(.system(size: 22, weight: .bold).width(.condensed))
                    .foregroundStyle(Theme.Colors.text)
                    .monospacedDigit()
            }
        }
    }

    private func stat<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
            value()
                .frame(height: 28)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart

    private var currentHour: Int { Calendar.current.component(.hour, from: summary.asOf) }

    private var peakMinutes: Double {
        let peak = summary.hours.map { $0.lockedMinutes + $0.otherMinutes }.max() ?? 0
        return max(peak, 20)
    }

    private func minutes(at hour: Int) -> (locked: Double, other: Double) {
        guard let bucket = summary.hours.first(where: { $0.id == hour }) else { return (0, 0) }
        return (bucket.lockedMinutes, bucket.otherMinutes)
    }

    private var chart: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                legendDot(color: Theme.Colors.textSecondary, label: Copy.screenTime.legendOther)
                legendDot(color: Theme.Colors.danger, label: Copy.screenTime.legendLocked)
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Self.chartHours, id: \.self) { hour in
                    bar(hour: hour)
                }
            }
            .frame(height: Self.chartHeight)

            HStack(spacing: 5) {
                ForEach(Self.chartHours, id: \.self) { hour in
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: 1)
                        .overlay {
                            if Self.axisHours.contains(hour) {
                                Text(Copy.screenTime.hourLabel(hour))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.muted)
                                    .fixedSize()
                            }
                        }
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    @ViewBuilder
    private func bar(hour: Int) -> some View {
        let isFuture = hour > currentHour
        let usage = minutes(at: hour)
        let scale = Self.chartHeight / peakMinutes
        let otherHeight = max(0, usage.other * scale)
        let lockedHeight = max(0, usage.locked * scale)
        if isFuture {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.Colors.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                if otherHeight > 0.5 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.Colors.text, Theme.Colors.lockedAmbient],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(3, otherHeight))
                }
                if lockedHeight > 0.5 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Colors.danger)
                        .frame(height: max(3, lockedHeight))
                }
                if otherHeight <= 0.5, lockedHeight <= 0.5 {
                    Capsule()
                        .fill(Theme.Colors.track)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if hour == currentHour {
                    Circle()
                        .fill(Theme.Colors.text)
                        .frame(width: 4, height: 4)
                        .offset(y: -8)
                }
            }
        }
    }

    // MARK: - List

    /// Time not on the phone since midnight: the day's elapsed time minus screen time.
    private var offline: (time: TimeInterval, percent: Int) {
        let start = Calendar.current.startOfDay(for: summary.asOf)
        let elapsed = max(summary.asOf.timeIntervalSince(start), 1)
        let off = max(0, elapsed - summary.total)
        return (off, Int((off / elapsed * 100).rounded()))
    }

    private var list: some View {
        VStack(spacing: 0) {
            row {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.Colors.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } title: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Copy.screenTime.timeOffline)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(Copy.screenTime.offlineShare(percent: offline.percent))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
            } value: {
                Text(Copy.screenTime.duration(offline.time))
                    .font(.system(.headline, weight: .semibold).width(.condensed))
                    .foregroundStyle(Theme.Colors.accent)
            }

            if summary.apps.isEmpty {
                divider
                Text(Copy.screenTime.noUsageYet)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
            }

            ForEach(summary.apps.prefix(Self.listLimit)) { app in
                divider
                row {
                    ScreenTimeAppIcon(app: app, size: 30)
                } title: {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        if app.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.Colors.danger)
                        }
                    }
                } value: {
                    Text(Copy.screenTime.duration(app.duration))
                        .font(.system(.headline, weight: .semibold).width(.condensed))
                        .foregroundStyle(app.isLocked ? Theme.Colors.danger : Theme.Colors.textSecondary)
                }
            }
        }
        .zanoCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: Theme.Metrics.edgeWidth)
            .padding(.leading, Theme.Spacing.md + 30 + Theme.Spacing.sm)
    }

    private func row<Icon: View, Title: View, Value: View>(
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            icon()
            title()
            Spacer(minLength: Theme.Spacing.xs)
            value()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

/// An app's icon: the real one via FamilyControls' `Label(token)` when there is a token, otherwise
/// (demo data) a tile with the app's initial.
struct ScreenTimeAppIcon: View {
    let app: ScreenTimeSummary.AppUsage
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        Group {
            if let token = app.token {
                Label(token)
                    .labelStyle(.iconOnly)
            } else {
                Text(String(app.name.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Theme.Colors.text)
                    .frame(width: size, height: size)
                    .background(tileColor, in: shape)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Colors.background, lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    /// A stable per-name hue for demo tiles.
    private var tileColor: Color {
        let palette = [Theme.Colors.Ring.creatine, Theme.Colors.Ring.sleepOnTime, Theme.Colors.Ring.stretchMobility, Theme.Colors.Ring.protein, Theme.Colors.Ring.water]
        let index = abs(app.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % palette.count
        return palette[index]
    }
}
