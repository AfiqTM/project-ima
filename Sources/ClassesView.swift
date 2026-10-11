import SwiftUI

struct ClassesView: View {
    @StateObject private var vm = PageViewModel(demo: DemoData.schedule) { Endpoints.schedule }
    @State private var day: Weekday = .today
    @State private var showWeb = false
    @AppStorage(UserName.key) private var fullName = ""

    private var classes: [ClassSession] {
        guard let page = vm.page, let t = TimetableParser.table(in: page) else { return [] }
        return TimetableParser.parse(t)
    }

    /// Only the weekdays that actually have a class (Mon...Sun order).
    private var availableDays: [Weekday] {
        Weekday.ordered.filter { d in classes.contains { $0.day == d } }
    }

    /// The selected day, falling back to today (if it has classes) or the first day with classes.
    private var activeDay: Weekday {
        if availableDays.contains(day) { return day }
        if availableDays.contains(Weekday.today) { return Weekday.today }
        return availableDays.first ?? day
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    GreetingTitle(name: UserName.shortName(fullName), subtitle: vm.page?.heading)
                    SessionMenu(links: vm.page?.dropdown ?? []) { url in
                        Task { await vm.load(url: url) }
                    }
                    .padding(.top, 6)
                }

                if !availableDays.isEmpty {
                    DayPicker(days: availableDays,
                              selected: Binding(get: { activeDay }, set: { day = $0 }))
                }

                NowCard(classes: classes, loading: vm.isLoading && vm.page == nil)

                dayList

                if vm.isOffline { OfflineNotice() }

                if let page = vm.page, classes.isEmpty, !vm.isLoading {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Page loaded, but no timetable was found", systemImage: "questionmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.accent)
                        Text("Tables found: \(page.tables.count). What the app can see:")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                        Text(String(page.text.prefix(350)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.txt.opacity(0.8))
                        Button("Open full page") { showWeb = true }
                            .buttonStyle(AccentButtonStyle(filled: false))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(16)
                }

                if let e = vm.errorMessage {
                    ErrorPanel(message: e,
                               retry: { Task { await vm.load() } },
                               openWeb: { showWeb = true })
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await vm.load() }
        .task {
            if WebSession.shared.state != .demo { NameFetcher.shared.fetchIfNeeded() }
            await vm.load()
        }
        .screenBackground()
        .sheet(isPresented: $showWeb) { WebSheet(url: Endpoints.schedule) }
    }

    @ViewBuilder
    private var dayList: some View {
        let items = classes.filter { $0.day == activeDay }.sorted { $0.start < $1.start }
        if !items.isEmpty {
            VStack(spacing: 12) {
                ForEach(items) { ClassCard(item: $0) }
            }
        }
    }
}

// MARK: - Now card (hero, the only card with the glow)

struct NowCard: View {
    let classes: [ClassSession]
    let loading: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let current = ClassSession.current(in: classes, at: ctx.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(current != nil ? Theme.good : Theme.muted.opacity(0.6))
                        .frame(width: 7, height: 7)
                    SectionLabel(current != nil ? "Happening now" : "Free right now")
                    Spacer()
                }

                if let c = current {
                    CodeTag(text: c.code)
                    Text(c.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.txt)
                        .lineLimit(2)
                    InfoRow(icon: "mappin.and.ellipse", text: c.venue)
                    InfoRow(icon: "clock", text: c.timeText)
                    progress(c, now: ctx.date)
                } else if loading {
                    Text("Loading your timetable…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.muted)
                } else if let n = ClassSession.next(in: classes, at: ctx.date) {
                    let when = ClassSession.dayLabel(offset: n.dayOffset, from: ctx.date)
                    Text("Next up")
                        .font(.system(size: 13)).foregroundColor(Theme.muted)
                    CodeTag(text: n.session.code)
                    Text(n.session.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.txt)
                        .lineLimit(2)
                    InfoRow(icon: "clock", text: "\(when), \(ClassSession.format(n.session.start))")
                } else {
                    Text("No classes right now")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.txt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glowCard(radius: 18)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func progress(_ c: ClassSession, now: Date) -> some View {
        let total = max(1, c.end - c.start)
        let done = min(1, max(0, Double(ClassSession.nowMinutes(now) - c.start) / Double(total)))
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(Theme.accent).frame(width: g.size.width * done)
            }
        }
        .frame(height: 4)
        .padding(.top, 2)
    }
}

// MARK: - Day picker

struct DayPicker: View {
    let days: [Weekday]
    @Binding var selected: Weekday

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { d in
                let isSel = d == selected
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selected = d }
                } label: {
                    Text(d.short)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSel ? Color.black : (d == Weekday.today ? Theme.accent : Theme.muted))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSel ? Theme.accent : Theme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSel ? Color.clear : Theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Class card (agenda row: time on the left, details on the right)

struct ClassCard: View {
    let item: ClassSession

    private var registered: Bool { item.status.lowercased().contains("registered") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CodeTag(text: item.code)
                Spacer(minLength: 0)
                if !item.status.isEmpty {
                    Text(item.status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(registered ? Theme.good : Theme.muted)
                }
            }
            Text(item.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.txt)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
                    .frame(width: 16)
                Text(item.timeText)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundColor(Theme.accent)
                Spacer(minLength: 0)
            }
            InfoRow(icon: "mappin.and.ellipse", text: item.venue)
            if !item.lecturer.isEmpty {
                InfoRow(icon: "person.fill", text: item.lecturer.capitalized, color: Theme.muted)
            }

            Hairline()

            Text("Section \(item.section)  ·  \(item.credit) credit hrs  ·  \(item.dayRaw)")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(14)
    }
}
