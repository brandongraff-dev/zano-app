// TimeOfDay.swift
// App / Features / SunriseAlarm
//
// The sky icon for the hour you are looking at the screen: a moon with stars at night, a rising sun
// at dawn, a full sun in the day and a setting sun at dusk. Used where the alarm screens show a
// small celestial glyph (the wake-time card's badge, the ringing screen's "Wake up" chip), so an
// alarm that rings at 3 a.m. shows a moon and one that rings at 6:30 shows a sunrise.

import SwiftUI
import Core

enum TimeOfDay: Equatable {
    case night
    case dawn
    case day
    case dusk

    /// Night is 20:00 to 04:59, dawn 05:00 to 08:59, day 09:00 to 16:59, dusk 17:00 to 19:59.
    init(date: Date = .now, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: date) {
        case 5..<9: self = .dawn
        case 9..<17: self = .day
        case 17..<20: self = .dusk
        default: self = .night
        }
    }

    var symbol: String {
        switch self {
        case .night: "moon.stars.fill"
        case .dawn: "sunrise.fill"
        case .day: "sun.max.fill"
        case .dusk: "sunset.fill"
        }
    }

    /// The glyph's tint on a neutral surface: moonlit periwinkle at night, sun yellow otherwise.
    var tint: Color {
        switch self {
        case .night: Theme.Colors.Ring.sleepOnTime
        case .dawn, .day, .dusk: Theme.Colors.Ring.sunriseAlarm
        }
    }
}
