//
//  ClockCalendarView.swift
//  AgoyNotch
//
//  The RIGHT column of the expanded notch panel: a LIVE clock (ticking every second) above a
//  compact calendar block (month label, a large current-day number, and a one-week strip of
//  weekday letters with today highlighted) — matching the NotchNook reference the user showed
//  next to the Now Playing section.
//
//  Local-only: EVERYTHING here is computed from `Date()` / `Calendar.current` /
//  `Locale.current` / `DateFormatter`. There is NO network, NO telemetry, and NO EventKit /
//  Calendar-events integration (which would need permissions and is out of scope) — the
//  "Nothing for today" line is a static, tasteful placeholder.
//
//  Live seconds without a manual Timer: the clock is driven by SwiftUI's
//  `TimelineView(.periodic(from: .now, by: 1))`, which re-evaluates its body every second
//  while the view is on screen and automatically pauses when it is not. That avoids a manual
//  `Timer` (no retain cycles, no teardown) and keeps everything on the main actor — a
//  `TimelineView` is a plain SwiftUI `View`, so there is no new background work.
//

import SwiftUI

/// The clock + calendar block rendered as the right column of the expanded panel. Text is
/// light/white on the dark panel to match the Now Playing styling.
struct ClockCalendarView: View {

    // MARK: - Formatters (locale-aware, built once)

    /// Live-clock formatter. Uses the user's locale/calendar but a fixed 24-hour pattern with
    /// seconds (HH:mm:ss). Built once; `DateFormatter` is reused across ticks.
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.calendar = Calendar.current
        // 24-hour clock with seconds. Fixed format (not localized template) so seconds are
        // always shown and always tick visibly.
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Month label formatter (e.g. "Aug"), localized to the user's locale.
    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.calendar = Calendar.current
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    // Weekday letters for the week strip come straight from the user's calendar/locale via
    // `Calendar.veryShortStandaloneWeekdaySymbols` (see `weekdayLetters`), so no formatter is
    // needed for them.

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // LIVE CLOCK — re-evaluated every second by the TimelineView, so the seconds tick
            // visibly while the panel is expanded. Auto-pauses when the view leaves screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timeFormatter.string(from: context.date))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            calendarBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Calendar block

    /// Month label + big current-day number, a one-week weekday strip with today highlighted,
    /// and a static placeholder line. Everything is derived from `Date()` once per redraw.
    private var calendarBlock: some View {
        let now = Date()
        let calendar = Calendar.current
        let dayNumber = calendar.component(.day, from: now)

        return VStack(alignment: .leading, spacing: 8) {
            // Month label + large day number, like the reference.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(monthFormatter.string(from: now))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(dayNumber)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // One-week strip: weekday letters with today highlighted.
            weekStrip(now: now, calendar: calendar)

            // Static placeholder (NO EventKit integration — see file header).
            Text("Nothing for today")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    /// The current week as 7 columns, each showing the locale's narrow weekday letter with the
    /// day number beneath; today's column is highlighted.
    private func weekStrip(now: Date, calendar: Calendar) -> some View {
        let days = currentWeekDays(now: now, calendar: calendar)
        let letters = weekdayLetters(calendar: calendar)
        let todayStart = calendar.startOfDay(for: now)

        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDate(day, inSameDayAs: todayStart)
                let weekdayIndex = (calendar.component(.weekday, from: day) - 1) % 7
                VStack(spacing: 3) {
                    Text(letters[weekdayIndex])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 11, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.black : .white.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(isToday ? Color.white : Color.clear)
                        )
                }
            }
        }
    }

    // MARK: - Date helpers (all local)

    /// The 7 days of the week containing `now`, ordered from the locale's first weekday.
    private func currentWeekDays(now: Date, calendar: Calendar) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: startOfToday) else {
            return [startOfToday]
        }
        var days: [Date] = []
        var day = weekInterval.start
        for _ in 0..<7 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The locale's narrow standalone weekday symbols (e.g. ["S","M","T","W","T","F","S"]),
    /// indexed 0 = Sunday … 6 = Saturday to match `Calendar`'s `.weekday` component.
    private func weekdayLetters(calendar: Calendar) -> [String] {
        let narrow = calendar.veryShortStandaloneWeekdaySymbols
        if narrow.count == 7 {
            return narrow
        }
        // Defensive fallback (should never trigger with a standard Gregorian calendar).
        return ["S", "M", "T", "W", "T", "F", "S"]
    }
}
