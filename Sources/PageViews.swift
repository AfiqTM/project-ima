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
                    ScreenHeader(title: "Exams", subtitle: nil)
                    SegmentBar(selection: $seg)
                    PageContent(vm: current)
                        .id(seg)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await current.load() }
            .task(id: seg) { await current.load() }
            .amoled()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct SegmentBar: View {
    @Binding var selection: ExamSegment

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ExamSegment.allCases) { s in
                let on = s == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = s }
                } label: {
                    Text(s.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(on ? Color.black : Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Services / Disciplinary / Co-Curriculum

struct SimplePageView: View {
    let title: String
    @StateObject private var vm: PageViewModel

    init(title: String, keys: [String]) {
        self.title = title
        _vm = StateObject(wrappedValue: PageViewModel { try await WebSession.shared.link(for: keys) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(title: title, subtitle: nil)
                    PageContent(vm: vm)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .amoled()
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
                    Text(h)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                PageContent(vm: vm)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .amoled()
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
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
                ErrorCard(message: e,
                          retry: { Task { await vm.load() } },
                          openWeb: { showWeb = true })
            }
            if vm.isOffline { OfflineBanner() }

            if let page = vm.page {
                SessionPill(links: page.dropdown) { url in
                    Task { await vm.load(url: url) }
                }
                ForEach(page.tables) { t in DataTable(table: t) }
                if !page.links.isEmpty { LinkList(links: page.links) }
                if page.tables.isEmpty && page.links.isEmpty && !page.text.isEmpty {
                    Text(String(page.text.prefix(1200)))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(18)
                }
                Button {
                    showWeb = true
                } label: {
                    Label("Open full page", systemImage: "safari")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.accentSoft)
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
                Text(table.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.accentSoft)
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
                        CodePill(text: title)
                    } else {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                ForEach(others, id: \.offset) { o in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if labeled {
                            Text(header[o.offset])
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.accent)
                                .frame(width: 112, alignment: .leading)
                        }
                        Text(o.element)
                            .font(.system(size: 14, weight: hasTitle ? .regular : .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
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
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                if let s = subtitle, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Theme.accentSoft)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                HStack { Spacer(); arrow }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .glassCard(18)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    if let s = subtitle, !s.isEmpty {
                        Text(s).font(.system(size: 12)).foregroundColor(Theme.accentSoft)
                    }
                }
                Spacer()
                arrow
            }
            .glassCard(16)
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
