import SwiftUI

// MARK: - Exams (CAMs / Final Exam / Result)

enum ExamSegment: String, CaseIterable, Identifiable {
    case cams = "CAMs"
    case finalExam = "Final Exam"
    case result = "Result"
    var id: String { rawValue }
}

struct ExamsView: View {
    @State private var seg: ExamSegment = .cams

    @StateObject private var cams = PageViewModel { try await WebSession.shared.link(for: ["continuous assessment marks", "continuous assessment"]) }
    @StateObject private var finalExam = PageViewModel { try await WebSession.shared.link(for: ["final exam"]) }
    @StateObject private var result = PageViewModel { try await WebSession.shared.link(for: ["result"]) }

    private var current: PageViewModel {
        switch seg {
        case .cams: return cams
        case .finalExam: return finalExam
        case .result: return result
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageTitle(title: "Exams")
                    SegmentBar(selection: $seg)
                    PageContent(vm: current)
                        .id(seg)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, tabBarInset)
            }
            .refreshable { await current.loadResilient() }
            .task(id: seg) { await current.loadResilient() }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// Underline tabs (same idea as the userscript's .nav-tabs: muted text, accent underline on the active one)
struct SegmentBar: View {
    @Binding var selection: ExamSegment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExamSegment.allCases) { s in
                let on = s == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = s }
                } label: {
                    VStack(spacing: 8) {
                        Text(s.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(on ? Theme.accent : Theme.muted)
                        Rectangle()
                            .fill(on ? Theme.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(alignment: .bottom) { Hairline() }
    }
}

// MARK: - Services / Disciplinary / Co-Curriculum

struct SimplePageView: View {
    let title: String
    let extra: (title: String, keys: [String])?
    @StateObject private var vm: PageViewModel
    @State private var extraLink: PageLink?

    init(title: String, keys: [String], extra: (title: String, keys: [String])? = nil) {
        self.title = title
        self.extra = extra
        _vm = StateObject(wrappedValue: PageViewModel { try await WebSession.shared.link(for: keys) })
    }

    /// Looks up the "Others" link, retrying a few times because the menu may not be ready on the first try.
    private func loadExtra() async {
        guard let e = extra, extraLink == nil, WebSession.shared.state != .demo else { return }
        for attempt in 0..<5 {
            if let u = try? await WebSession.shared.link(for: e.keys) {
                extraLink = PageLink(text: e.title, href: u.absoluteString)
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(600_000_000 * (attempt + 1)))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageTitle(title: title)
                    PageContent(vm: vm, extraLink: extraLink, placeAfter: "counsel")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, tabBarInset)
            }
            .refreshable { await vm.loadResilient() }
            .task {
                // Fetch the extra link in its own task so it neither waits for the page load nor gets cancelled with it.
                Task { await loadExtra() }
                await vm.loadResilient()
            }
            .onChange(of: vm.page) { _ in
                if extraLink == nil { Task { await loadExtra() } }
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Drill-down page (e.g. detailed result for one semester)

struct DetailPageView: View {
    let url: URL
    @StateObject private var vm: PageViewModel
    @State private var showWeb = false

    init(url: URL) {
        self.url = url
        _vm = StateObject(wrappedValue: PageViewModel { url })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let h = vm.page?.heading, !h.isEmpty {
                    PageTitle(title: h)
                }
                PageContent(vm: vm)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, tabBarInset)
        }
        .refreshable { await vm.loadResilient() }
        .task { await vm.loadResilient() }
        .screenBackground()
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showWeb = true } label: { Image(systemName: "safari") }
            }
        }
        .sheet(isPresented: $showWeb) { WebSheet(url: url) }
    }
}

// MARK: - Generic renderer for scraped pages

struct PageContent: View {
    @ObservedObject var vm: PageViewModel
    @State private var showWeb = false
    var extraLink: PageLink? = nil
    var placeAfter: String = ""

    private func merged(_ links: [PageLink]) -> [PageLink] {
        guard let x = extraLink, !links.contains(where: { $0.href == x.href }) else { return links }
        var out = links
        if !placeAfter.isEmpty,
           let i = out.firstIndex(where: { $0.text.lowercased().contains(placeAfter) }) {
            out.insert(x, at: i + 1)
        } else {
            out.append(x)
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if vm.isLoading && vm.page == nil {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .padding(.vertical, 40)
            }
            if let e = vm.errorMessage {
                ErrorPanel(message: e,
                           retry: { Task { await vm.loadResilient() } },
                           openWeb: { showWeb = true })
            }
            if vm.isOffline { OfflineNotice() }

            if let page = vm.page {
                HStack {
                    Spacer()
                    SessionMenu(links: page.dropdown) { url in
                        Task { await vm.loadResilient(url: url) }
                    }
                }
                let summaries = page.tables.flatMap { $0.rows }.compactMap { SummaryParser.parse($0) }
                let tables = page.tables.compactMap { t -> WebTable? in
                    let rows = t.rows.filter { SummaryParser.parse($0) == nil }
                    if rows.isEmpty { return nil }
                    if rows.count < t.rows.count && rows.count <= 1 { return nil }
                    return WebTable(id: t.id, title: t.title, rows: rows)
                }
                ForEach(summaries.indices, id: \.self) { SummaryCard(blocks: summaries[$0]) }
                ForEach(tables) { t in DataTable(table: t) }
                let links = merged(page.links)
                if !links.isEmpty { LinkList(links: links) }
                if tables.isEmpty && summaries.isEmpty && links.isEmpty && !page.text.isEmpty {
                    Text(String(page.text.prefix(1200)))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.txt.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(16)
                }
                Button {
                    showWeb = true
                } label: {
                    Label("Open full page", systemImage: "safari")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showWeb) { WebSheet(url: vm.currentURL ?? Endpoints.base) }
    }
}

struct DataTable: View {
    let table: WebTable

    var body: some View {
        let hasHeader = table.rows.count > 1
        let header = hasHeader ? table.rows[0].cells : []
        let dataRows = hasHeader ? Array(table.rows.dropFirst()) : table.rows
        VStack(alignment: .leading, spacing: 10) {
            if !table.title.isEmpty {
                SectionLabel(table.title)
            }
            ForEach(Array(dataRows.enumerated()), id: \.offset) { _, row in
                RowCard(header: header, row: row)
            }
        }
    }
}

struct RowCard: View {
    let header: [String]
    let row: WebRow
    @State private var showWeb = false

    var body: some View {
        if let h = row.href, let url = URL(string: h) {
            if url.isReadableInApp {
                NavigationLink {
                    DetailPageView(url: url)
                } label: {
                    content(chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                Button { showWeb = true } label: { content(chevron: true) }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showWeb) { WebSheet(url: url) }
            }
        } else {
            content(chevron: false)
        }
    }

    private func content(chevron: Bool) -> some View {
        let cells = row.cells
        let titleIndex = cells.firstIndex { !$0.isEmpty } ?? 0
        let title = cells.isEmpty ? "" : cells[titleIndex]
        let labeled = header.count == cells.count
        let pill = cells.count > 2 && title.range(of: "^[A-Za-z]{3,5} ?[0-9]{3,4}", options: .regularExpression) != nil
        // Label/value tables without a course code (e.g. GPA summaries) show every field as a pair.
        let hasTitle = pill || !labeled
        let others = cells.enumerated().filter { (!hasTitle || $0.offset != titleIndex) && !$0.element.isEmpty }

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                if hasTitle {
                    if pill {
                        CodeTag(text: title)
                    } else {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.txt)
                    }
                }
                ForEach(others, id: \.offset) { o in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if labeled {
                            Text(header[o.offset])
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.muted)
                                .frame(width: 108, alignment: .leading)
                        }
                        Text(o.element)
                            .font(.system(size: 14, weight: hasTitle ? .regular : .semibold))
                            .foregroundColor(Theme.txt)
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.muted)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(14)
    }
}

struct LinkList: View {
    let links: [PageLink]

    private var isTileGrid: Bool { links.contains { ($0.subtitle ?? "").isEmpty == false } }

    var body: some View {
        if isTileGrid {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(links) { l in
                    if let url = URL(string: l.href) {
                        LinkRow(text: l.text, subtitle: l.subtitle, url: url, tile: true)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(links) { l in
                    if let url = URL(string: l.href) {
                        LinkRow(text: l.text, subtitle: l.subtitle, url: url, tile: false)
                    }
                }
            }
        }
    }
}

struct LinkRow: View {
    let text: String
    let subtitle: String?
    let url: URL
    let tile: Bool
    @State private var showWeb = false

    private var arrow: some View {
        Image(systemName: url.isReadableInApp ? "chevron.right" : "arrow.up.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Theme.accent)
    }

    @ViewBuilder
    private var label: some View {
        if tile {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.txt)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                if let s = subtitle, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                HStack { Spacer(); arrow }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .card(14)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.txt)
                        .multilineTextAlignment(.leading)
                    if let s = subtitle, !s.isEmpty {
                        Text(s).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
                Spacer()
                arrow
            }
            .card(14)
        }
    }

    var body: some View {
        if url.isReadableInApp {
            NavigationLink { DetailPageView(url: url) } label: { label }
                .buttonStyle(.plain)
        } else {
            Button { showWeb = true } label: { label }
                .buttonStyle(.plain)
                .sheet(isPresented: $showWeb) { WebSheet(url: url) }
        }
    }
}

// MARK: - GPA / CGPA summary box

struct SummaryCard: View {
    let blocks: [[SummaryPair]]

    private func isCGPA(_ p: SummaryPair) -> Bool { p.label.lowercased().contains("cgpa") }
    private func isGPA(_ p: SummaryPair) -> Bool {
        let l = p.label.lowercased()
        return l.contains("gpa") && !l.contains("cgpa") && !l.contains("cumulative")
    }

    private func hero(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title)
            Text(value)
                .font(.system(size: 34, weight: .bold).monospacedDigit())
                .foregroundColor(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
    }

    private func detail(_ p: SummaryPair) -> some View {
        let v = p.value.uppercased()
        let color: Color = v == "PASS" ? Theme.good : (v == "FAIL" ? Theme.bad : Theme.txt)
        return HStack(alignment: .firstTextBaseline) {
            Text(p.label)
                .font(.system(size: 14))
                .foregroundColor(Theme.muted)
            Spacer(minLength: 12)
            Text(p.value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
        }
    }

    var body: some View {
        let all = blocks.flatMap { $0 }
        let gpa = all.first { isGPA($0) }
        let cgpa = all.first { isCGPA($0) }
        VStack(alignment: .leading, spacing: 14) {
            if gpa != nil || cgpa != nil {
                HStack(spacing: 12) {
                    if let g = gpa { hero("GPA", g.value) }
                    if let c = cgpa { hero("CGPA", c.value) }
                }
            }
            ForEach(blocks.indices, id: \.self) { b in
                if b > 0 { Hairline() }
                VStack(spacing: 9) {
                    ForEach(blocks[b].filter { !isGPA($0) && !isCGPA($0) }) { detail($0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glowCard(radius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
