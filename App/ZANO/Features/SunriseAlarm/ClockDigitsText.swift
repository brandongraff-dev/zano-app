// ClockDigitsText.swift
// App / Features / SunriseAlarm
//
// The big alarm clock numerals: the digits in the app's expanded black face, with "AM"/"PM" as a
// smaller second run on a 12-hour clock. Shared by the ringing screen and the bedtime card.
//
// Why not `Theme.Typography.score`: that face forces every digit to the width of the widest one, so
// a "1" gets a full-width slot and "11:39" or "10:30" reads with a hole after the 1. These clocks
// change at most once a minute, so proportional digits cost nothing.

import SwiftUI
import Core

struct ClockDigitsText: View {
    let date: Date
    let size: CGFloat

    var body: some View {
        let parts = Self.parts(for: date)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(parts.digits)
                .font(Self.font(size))
            if let period = parts.period {
                Text(period)
                    .font(Self.font(size * 0.38))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.hour().minute()))
    }

    static func font(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded)
    }

    /// The time as digits plus, on a 12-hour clock, a separate "AM"/"PM".
    static func parts(for date: Date) -> (digits: String, period: String?) {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        let is12Hour = template.contains("a")
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = is12Hour ? "h:mm" : "HH:mm"
        let digits = formatter.string(from: date)
        guard is12Hour else { return (digits, nil) }
        formatter.dateFormat = "a"
        return (digits, formatter.string(from: date))
    }
}
