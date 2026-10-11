import Foundation

// MARK: - Generic scraped page

struct WebRow: Codable, Hashable {
    let cells: [String]
    let href: String?
}

struct WebTable: Codable, Identifiable, Hashable {
    var id = UUID()
    let title: String
    let rows: [WebRow]
    enum CodingKeys: String, CodingKey { case title, rows }
}

struct PageLink: Codable, Identifiable, Hashable {
    var id = UUID()
    let text: String
    let href: String
    enum CodingKeys: String, CodingKey { case text, href }
}

struct PageData: Codable, Hashable {
    let heading: String
    let tables: [WebTable]
    let dropdown: [PageLink]
    let links: [PageLink]
    let text: String
}

enum PageCache {
    private static func key(_ url: URL) -> String { "page:" + url.absoluteString }

    static func save(_ page: PageData, for url: URL) {
        if let d = try? JSONEncoder().encode(page) {
            UserDefaults.standard.set(d, forKey: key(url))
        }
    }

    static func load(_ url: URL) -> PageData? {
        guard let d = UserDefaults.standard.data(forKey: key(url)) else { return nil }
        return try? JSONDecoder().decode(PageData.self, from: d)
    }

    static func hasAny() -> Bool {
        UserDefaults.standard.dictionaryRepresentation().keys.contains { $0.hasPrefix("page:") }
    }

    static func clear() {
        let ud = UserDefaults.standard
        for k in ud.dictionaryRepresentation().keys where k.hasPrefix("page:") {
            ud.removeObject(forKey: k)
        }
    }
}

// MARK: - Timetable

enum Weekday: Int, CaseIterable, Identifiable {
    case sun = 1, mon, tue, wed, thu, fri, sat
    var id: Int { rawValue }

    static let ordered: [Weekday] = [.mon, .tue, .wed, .thu, .fri, .sat, .sun]

    static var today: Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: Date())) ?? .mon
    }

    var short: String {
        switch self {
        case .sun: return "Sun"
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        }
    }

    var full: String {
        switch self {
        case .sun: return "Sunday"
        case .mon: return "Monday"
        case .tue: return "Tuesday"
        case .wed: return "Wednesday"
        case .thu: return "Thursday"
        case .fri: return "Friday"
        case .sat: return "Saturday"
        }
    }
}

struct ClassSession: Identifiable, Hashable {
    let id = UUID()
    let code: String
    let name: String
    let section: String
    let credit: String
    let status: String
    let day: Weekday
    let dayRaw: String
    let start: Int   // minutes since midnight
    let end: Int
    let venue: String
    let lecturer: String

    static func format(_ minutes: Int) -> String {
        let h = (minutes / 60) % 24
        let m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, h < 12 ? "AM" : "PM")
    }

    /// e.g. "1:00 PM – 3:00 PM"
    var timeText: String { "\(Self.format(start)) – \(Self.format(end))" }

    static func nowMinutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func weekday(_ d: Date) -> Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: d)) ?? .mon
    }

    static func dayLabel(offset: Int, from date: Date) -> String {
        if offset == 0 { return "Today" }
        if offset == 1 { return "Tomorrow" }
        let d = Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date
        return weekday(d).full
    }

    static func current(in list: [ClassSession], at date: Date) -> ClassSession? {
        let wd = weekday(date)
        let m = nowMinutes(date)
        return list.first { $0.day == wd && $0.start <= m && m < $0.end }
    }

    static func next(in list: [ClassSession], at date: Date) -> (session: ClassSession, dayOffset: Int)? {
        let m = nowMinutes(date)
        for offset in 0...7 {
            guard let d = Calendar.current.date(byAdding: .day, value: offset, to: date) else { continue }
            let wd = weekday(d)
            let candidates = list
                .filter { $0.day == wd && (offset > 0 || $0.start > m) }
                .sorted { $0.start < $1.start }
            if let f = candidates.first { return (f, offset) }
        }
        return nil
    }
}

enum TimetableParser {
    static let dayMap: [String: Weekday] = [
        "M": .mon, "MON": .mon, "T": .tue, "TUE": .tue, "W": .wed, "WED": .wed,
        "TH": .thu, "THU": .thu, "F": .fri, "FRI": .fri, "S": .sat, "SAT": .sat,
        "SU": .sun, "SUN": .sun
    ]

    static func table(in page: PageData) -> WebTable? {
        let match = page.tables.first { t in
            guard let h = t.rows.first?.cells.map({ $0.lowercased() }) else { return false }
            return h.contains { $0.contains("code") } && h.contains { $0.contains("time") }
        }
        return match ?? page.tables.first
    }

    static func parseDays(_ s: String) -> [Weekday] {
        let tokens = s.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: "-,/& "))
            .filter { !$0.isEmpty }
        var out: [Weekday] = []
        for t in tokens {
            if let d = dayMap[t], !out.contains(d) { out.append(d) }
        }
        return out
    }

    static func parseTime(_ s: String) -> (Int, Int)? {
        let nums = s.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        func mins(_ v: Int) -> Int { (v / 100) * 60 + v % 100 }
        if nums.count >= 4, let h1 = Int(nums[0]), let m1 = Int(nums[1]), let h2 = Int(nums[2]), let m2 = Int(nums[3]) {
            return (h1 * 60 + m1, h2 * 60 + m2)
        }
        guard nums.count >= 2, let a = Int(nums[0]), let b = Int(nums[1]) else { return nil }
        return (mins(a), mins(b))
    }

    static func parse(_ table: WebTable) -> [ClassSession] {
        guard let headerRow = table.rows.first else { return [] }
        let h = headerRow.cells.map { $0.lowercased() }
        func idx(_ key: String) -> Int? { h.firstIndex { $0.contains(key) } }
        let iCode = idx("code"), iName = idx("name"), iSect = idx("sect"), iChr = idx("chr")
        let iStatus = idx("status"), iDay = idx("day"), iTime = idx("time")
        let iVenue = idx("venue"), iLect = idx("lecturer")

        var last = (code: "", name: "", sect: "", chr: "", status: "")
        var result: [ClassSession] = []

        for row in table.rows.dropFirst() {
            let c = row.cells
            // Continuation rows (e.g. a 2nd meeting day) can omit leading cells; right-align them.
            let shift = c.count < h.count ? h.count - c.count : 0
            func cell(_ i: Int?) -> String {
                guard let i = i, i - shift >= 0, i - shift < c.count else { return "" }
                return c[i - shift]
            }

            var code = cell(iCode)
            var name = cell(iName), sect = cell(iSect), chr = cell(iChr), status = cell(iStatus)
            if code.isEmpty {
                code = last.code; name = last.name; sect = last.sect; chr = last.chr; status = last.status
            } else {
                last = (code, name, sect, chr, status)
            }
            guard !code.isEmpty, let range = parseTime(cell(iTime)) else { continue }
            let dayRaw = cell(iDay)
            let venue = cell(iVenue)
            for d in parseDays(dayRaw) {
                result.append(ClassSession(
                    code: code, name: name, section: sect, credit: chr, status: status,
                    day: d, dayRaw: dayRaw, start: range.0, end: range.1,
                    venue: venue.isEmpty ? "Venue TBA" : venue,
                    lecturer: cell(iLect)))
            }
        }
        return result
    }
}

// MARK: - Demo data (from the sample timetable)

enum DemoData {
    static let schedule: PageData = {
        func r(_ c: [String]) -> WebRow { WebRow(cells: c, href: nil) }
        let rows: [WebRow] = [
            r(["Code", "Name", "Sect", "Chr", "Status", "Day", "Time", "Venue", "Lecturer"]),
            r(["BICS 1306", "Digital & Embedded Systems", "4", "3", "Registered", "M-W", "1000 - 1120", "ICT LT 1 LEVEL 4D", "ASMARANI BINTI AHMAD PUZI"]),
            r(["BICS 2301", "Enterprise Networks", "3", "3", "Registered", "T-TH", "1130 - 1250", "ICT CISCO LAB LEVEL 4C", "ADAMU ABUBAKAR IBRAHIM"]),
            r(["BICS 2303", "Intelligent Systems", "3", "3", "Registered", "T-TH", "1000 - 1120", "ICT LT 2 LEVEL 4D", "DINI OKTARINA DWI HANDAYANI"]),
            r(["BICS 2306", "Software Engineering", "5", "3", "Registered", "M-W", "1130 - 1250", "ICT TL-E5-01 LEVEL 5E", "SITI ASMA BINTI MOHAMMED"]),
            r(["BIIT 2301", "User Experience Design", "4", "3", "Registered", "M-W", "1400 - 1520", "ICT HCI LAB LEVEL 4C", "ELIN ELIANA BINTI ABDUL RAHIM"]),
            r(["CCFM 2061", "FAMILY MANAGEMENT", "31", ".5", "Registered", "TUE", "2000 - 2200", "KENMS 4.3 LEVEL 4", "SUZANA SUHAILAWATY BINTI MD. SIDEK"]),
            r(["LEED 1301", "ENGLISH FOR ACADEMIC WRITING", "51", "3", "Registered", "MON", "830 - 1000", "", "NURZAHIYAH BINTI ABU HASSAN"]),
            r(["", "", "", "", "", "WED", "830 - 1000", "", "NURZAHIYAH BINTI ABU HASSAN"])
        ]
        return PageData(heading: "Schedule sem 1, 2026/2027",
                        tables: [WebTable(title: "", rows: rows)],
                        dropdown: [], links: [], text: "")
    }()

    static let placeholder = PageData(
        heading: "Demo mode", tables: [], dropdown: [], links: [],
        text: "Sign in with your i-Ma'luum account to see your real data on this tab.")
}


extension URL {
    /// True for i-Ma'luum HTML pages we can read natively (not other sites, not PDFs/downloads).
    var isReadableInApp: Bool {
        guard host?.hasSuffix("imaluum.iium.edu.my") == true else { return false }
        let ext = pathExtension.lowercased()
        return !["pdf", "doc", "docx", "xls", "xlsx", "zip", "png", "jpg", "jpeg"].contains(ext)
    }
}
