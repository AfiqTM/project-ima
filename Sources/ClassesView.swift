import SwiftUI

struct ClassesView: View {
    @StateObject private var vm = PageViewModel(demo: DemoData.schedule) { Endpoints.schedule }
    @State private var day: Weekday = .today
    @State private var showWeb = false

    private var classes: [ClassSession] {
        guard let page = vm.page, let t = TimetableParser.table(in: page) else { return [] }
        return TimetableParser.parse(t)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NowCard(classes: classes, loading: vm.isLoading && vm.page == nil)

                ScreenHeader(title: "My Class Timetable", subtitle: vm.page?.heading)

                SessionPill(links: vm.page?.dropdown ?? []) { url in
                    Task { await vm.load(url: url) }
                }

                DayPicker(selected: $day, classes: classes)

                dayList

                if vm.isOffline { OfflineBanner() }
                if let page = vm.page, classes.isEmpty, !vm.isLoading {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Page loaded, but no timetable was found", systemImage: "questionmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.accentSoft)
                        Text("Tables found: \(page.tables.count). What the app can see:")
                            .font(.system(size: 12)).foregroundColor(Theme.textSecondary)
                        Text(String(page.text.prefix(350)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Button("Open full page") { showWeb = true }
                            .buttonStyle(.bordered).tint(Theme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(18)
                }
                if let e = vm.errorMessage {
                    ErrorCard(message: e,
                              retry: { Task { await vm.load() } },
                              openWeb: { showWeb = true })
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .amoled()
        .sheet(isPresented: $showWeb) { WebSheet(url: Endpoints.schedule) }
    }

    @ViewBuilder
    private var dayList: some View {
        let items = classes.filter { $0.day == day }.sorted { $0.start < $1.start }
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.accent)
                Text("No classes on \(day.full)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .glassCard()
        } else {
            ForEach(items) { ClassCard(item: $0) }
        }
    }
}

// MARK: - Now card

struct NowCard: View {
    let classes: [ClassSession]
    let loading: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let current = ClassSession.current(in: classes, at: ctx.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(current != nil ? Theme.success : Color.white.opacity(0.35))
                        .frame(width: 8, height: 8)
                    Text(current != nil ? "Happening now" : "Right now")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.accentSoft)
                    Spacer()
                }

                if let c = current {
                    HStack(spacing: 10) {
                        CodePill(text: c.code)
                        Text(c.name)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    Label(c.venue, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Label(c.timeText, systemImage: "clock")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    progress(c, now: ctx.date)
                } else if loading {
                    Text("Loading your timetable…")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                } else {
                    Text("No classes right now")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let n = ClassSession.next(in: classes, at: ctx.date) {
                        let when = ClassSession.dayLabel(offset: n.dayOffset, from: ctx.date)
                        Text("Next: \(n.session.code) · \(when), \(ClassSession.format(n.session.start))")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(26)
        }
    }

    private func progress(_ c: ClassSession, now: Date) -> some View {
        let total = max(1, c.end - c.start)
        let done = min(1, max(0, Double(ClassSession.nowMinutes(now) - c.start) / Double(total)))
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(Theme.pillGradient).frame(width: g.size.width * done)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Day picker

struct DayPicker: View {
    @Binding var selected: Weekday
    let classes: [ClassSession]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.ordered) { d in
                let isSel = d == selected
                let count = classes.filter { $0.day == d }.count
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = d }
                } label: {
                    VStack(spacing: 4) {
                        Text(d.short)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Circle()
                            .fill(count > 0 ? (isSel ? Color.black.opacity(0.55) : Theme.accent) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundColor(isSel ? Color.black : Color.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSel ? Theme.accent : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(d == Weekday.today ? Theme.accentSoft.opacity(0.7) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Class card (mirrors the reference design)

struct ClassCard: View {
    let item: ClassSession

    private var statusColor: Color {
        item.status.lowercased().contains("registered") ? Theme.success : Color.white.opacity(0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CodePill(text: item.code)
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").foregroundColor(Theme.textSecondary)
                Text("Sect: \(item.section)  |  Chr: \(item.credit)")
                    .foregroundColor(.white.opacity(0.9))
                Text("•  \(item.status)").foregroundColor(statusColor)
            }
            .font(.system(size: 13, design: .rounded))

            Label("\(item.dayRaw)  |  \(item.timeText)", systemImage: "clock")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            Label(item.venue, systemImage: "mappin.and.ellipse")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            Divider().overlay(Color.white.opacity(0.12))

            Label(item.lecturer, systemImage: "person.fill")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.accentSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
