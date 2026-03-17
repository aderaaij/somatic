import SwiftUI

// MARK: - Week Strip View

struct WeekStripView: View {
    let timelineItems: [DateComponents: [TrainingTimelineItem]]
    @Binding var selectedDate: Date

    @State private var scrolledWeek: Date?

    private let calendar = Calendar.current

    /// Generate week start dates: 13 weeks back and 13 weeks forward from today.
    private var weekStarts: [Date] {
        let today = Date()
        guard let todayWeekStart = startOfWeek(containing: today) else { return [] }
        return (-13...13).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0, to: todayWeekStart)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(selectedDate, format: .dateTime.month(.wide).year())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(weekStarts, id: \.self) { weekStart in
                        weekRow(for: weekStart)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledWeek)
            .frame(height: 76)
        }
        .onAppear {
            scrolledWeek = startOfWeek(containing: selectedDate)
        }
    }

    // MARK: - Week Row

    private func weekRow(for weekStart: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(daysInWeek(from: weekStart), id: \.self) { date in
                WeekDayCell(
                    date: date,
                    isToday: calendar.isDateInToday(date),
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    dotCategories: dotCategories(for: date)
                )
                .onTapGesture {
                    selectedDate = date
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func startOfWeek(containing date: Date) -> Date? {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)
    }

    private func daysInWeek(from weekStart: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func dotCategories(for date: Date) -> Set<TrainingTimelineItem.DotCategory> {
        let dc = calendar.dateComponents([.year, .month, .day], from: date)
        guard let items = timelineItems[dc] else { return [] }
        return Set(items.map(\.dotCategory))
    }
}

// MARK: - Week Day Cell

struct WeekDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let dotCategories: Set<TrainingTimelineItem.DotCategory>

    var body: some View {
        VStack(spacing: 4) {
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : .secondary)

            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)

            HStack(spacing: 3) {
                if dotCategories.contains(.upcomingPlan) {
                    Circle().fill(.blue).frame(width: 5, height: 5)
                }
                if dotCategories.contains(.completedPlan) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                }
                if dotCategories.contains(.pastWorkout) {
                    Circle().fill(.orange).frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor)
            } else if isToday {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }
}
