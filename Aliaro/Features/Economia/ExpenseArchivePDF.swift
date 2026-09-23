import SwiftUI
import UIKit

extension ExpenseArchive {
    /// "12 Jan 2026 – 3 Mar 2026" (or a single date if it all happened the same day).
    var periodText: String {
        let start = startDate.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) { return start }
        return "\(start) – \(endDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// Exports an `ExpenseArchive` as an A4 PDF: Aliaro logo + wordmark,
/// archive name and period, totals, balance between members at the time
/// of archiving, and the full list of transactions (paginated). Each page
/// is a SwiftUI view rendered straight into a PDF context, so text stays
/// vector and the look matches the app's design system.
@MainActor
enum ExpenseArchivePDF {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    fileprivate static let margin: CGFloat = 40
    fileprivate static let rowHeight: CGFloat = 24
    fileprivate static let footerHeight: CGFloat = 28

    /// Writes the PDF to a temporary file and returns its URL, ready to share.
    static func make(for archive: ExpenseArchive) throws -> URL {
        let date = archive.createdAt.formatted(date: .abbreviated, time: .shortened)
        let detail: String
        if let by = archive.archivedByName, !by.isEmpty {
            detail = String(localized: "Archived on \(date) by \(by)")
        } else {
            detail = String(localized: "Archived on \(date)")
        }
        return try render(PDFContent(
            name: archive.name, period: archive.periodText, detail: detail, snapshot: archive.snapshot
        ))
    }

    /// PDF of the live (not archived) finances, so they can be kept or
    /// sent without starting again from zero.
    static func makeCurrent(expenses: [Expense], categories: [ExpenseCategory], members: [FamilyMember]) throws -> URL {
        let snapshot = ExpenseArchiveSnapshot(expenses: expenses, categories: categories, members: members)
        let dates = expenses.map(\.occurredAt)
        let start = dates.min() ?? .now
        let end = dates.max() ?? .now
        var period = start.formatted(date: .abbreviated, time: .omitted)
        if !Calendar.current.isDate(start, inSameDayAs: end) {
            period += " – \(end.formatted(date: .abbreviated, time: .omitted))"
        }
        let generated = Date.now.formatted(date: .abbreviated, time: .shortened)
        return try render(PDFContent(
            name: String(localized: "Current finances"),
            period: period,
            detail: String(localized: "Generated on \(generated)"),
            snapshot: snapshot
        ))
    }

    private static func render(_ content: PDFContent) throws -> URL {
        let pages = paginate(content.snapshot)

        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeName = content.name.components(separatedBy: unsafe).joined(separator: "-").trimmed
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aliaro - \(safeName.isEmpty ? "Finances" : safeName).pdf")
        try? FileManager.default.removeItem(at: url)

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [String: Any] = [kCGPDFContextTitle as String: content.name, kCGPDFContextCreator as String: "Aliaro"]
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }

        for (index, rows) in pages.enumerated() {
            let page = ExpenseArchivePDFPage(
                content: content, rows: rows, pageIndex: index, pageCount: pages.count
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }

    /// Splits the transactions into pages. The first page also carries the
    /// big header, totals and balance, so it fits fewer rows.
    private static func paginate(_ snapshot: ExpenseArchiveSnapshot) -> [[ExpenseArchiveSnapshot.Item]] {
        let usable = pageSize.height - margin * 2 - footerHeight
        let settlementsHeight: CGFloat = snapshot.settlements.isEmpty ? 0 : 44 + CGFloat(snapshot.settlements.count) * 20
        let firstHeader: CGFloat = 300 + settlementsHeight
        let otherHeader: CGFloat = 80
        let firstCapacity = max(3, Int((usable - firstHeader) / rowHeight))
        let otherCapacity = max(10, Int((usable - otherHeader) / rowHeight))

        var remaining = snapshot.items[...]
        var pages: [[ExpenseArchiveSnapshot.Item]] = [Array(remaining.prefix(firstCapacity))]
        remaining = remaining.dropFirst(firstCapacity)
        while !remaining.isEmpty {
            pages.append(Array(remaining.prefix(otherCapacity)))
            remaining = remaining.dropFirst(otherCapacity)
        }
        return pages
    }
}

private struct PDFContent {
    let name: String
    let period: String
    /// "Archived on … by …" / "Generated on …".
    let detail: String
    let snapshot: ExpenseArchiveSnapshot
}

/// Fixed light palette: a PDF is printed/shared, it never follows dark mode.
private enum PDFColors {
    static let ink = ALIPalette.inkLight
    static let muted = ALIPalette.mutedInkLight
    static let outline = ALIPalette.outlineLight
    static let stripe = ALIPalette.surfaceVariantLight.opacity(0.55)
    static let accent = ALIColors.economiaAccent
}

private struct ExpenseArchivePDFPage: View {
    let content: PDFContent
    let rows: [ExpenseArchiveSnapshot.Item]
    let pageIndex: Int
    let pageCount: Int

    private var isFirstPage: Bool { pageIndex == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirstPage {
                fullHeader
            } else {
                compactHeader
            }
            if !rows.isEmpty {
                tableHeader
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    row(item, striped: index.isMultiple(of: 2))
                }
            } else if isFirstPage {
                Text("No transactions")
                    .font(.system(size: 11))
                    .foregroundStyle(PDFColors.muted)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ExpenseArchivePDF.margin)
        .padding(.top, ExpenseArchivePDF.margin)
        .padding(.bottom, ExpenseArchivePDF.margin + ExpenseArchivePDF.footerHeight)
        .frame(width: ExpenseArchivePDF.pageSize.width, height: ExpenseArchivePDF.pageSize.height, alignment: .top)
        .overlay(alignment: .bottom) { footer }
        .background(Color.white)
        .clipped()
    }

    // MARK: Header

    private var brand: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: isFirstPage ? 40 : 26, height: isFirstPage ? 40 : 26)
                .clipShape(RoundedRectangle(cornerRadius: isFirstPage ? 10 : 7, style: .continuous))
            AliaroWordmark(size: isFirstPage ? 26 : 17, textColor: PDFColors.ink)
            Spacer()
            Text("Finances")
                .font(.system(size: isFirstPage ? 12 : 10, weight: .semibold, design: .rounded))
                .foregroundStyle(PDFColors.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(PDFColors.accent.opacity(0.45))
                .clipShape(Capsule())
        }
    }

    private var fullHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            Rectangle().fill(PDFColors.outline).frame(height: 1).padding(.vertical, 16)

            Text(content.name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(PDFColors.ink)
                .lineLimit(2)
            Text(content.period)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(PDFColors.ink)
            .padding(.top, 6)
            Text(content.detail)
                .font(.system(size: 10))
                .foregroundStyle(PDFColors.muted)
                .padding(.top, 4)

            HStack(spacing: 10) {
                summaryTile(title: "Spent", value: content.snapshot.totalExpenses.formattedEuros)
                summaryTile(title: "Income", value: content.snapshot.totalIncome.formattedEuros)
                summaryTile(title: "Net expense", value: content.snapshot.net.formattedEuros, highlighted: true)
            }
            .padding(.top, 18)

            if !content.snapshot.settlements.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Balance between you")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PDFColors.muted)
                    ForEach(Array(content.snapshot.settlements.enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 4) {
                            Text(s.from).fontWeight(.semibold)
                            Text("owes")
                            Text(s.to).fontWeight(.semibold)
                            Spacer()
                            Text(s.amount.formattedEuros).fontWeight(.semibold)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(PDFColors.ink)
                        .frame(height: 14)
                    }
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PDFColors.outline, lineWidth: 1))
                .padding(.top, 14)
            }

            Text("Transactions (\(content.snapshot.items.count))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PDFColors.ink)
                .padding(.top, 20)
                .padding(.bottom, 8)
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            Text("\(content.name) · \(content.period)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PDFColors.muted)
                .lineLimit(1)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
    }

    private func summaryTile(title: LocalizedStringKey, value: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PDFColors.muted)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PDFColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? PDFColors.accent.opacity(0.35) : PDFColors.stripe)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Table

    private let dateWidth: CGFloat = 72
    private let personWidth: CGFloat = 96
    private let amountWidth: CGFloat = 82

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("Date").frame(width: dateWidth, alignment: .leading)
            Text("Concept").frame(maxWidth: .infinity, alignment: .leading)
            Text("Paid by").frame(width: personWidth, alignment: .leading)
            Text("Amount").frame(width: amountWidth, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(PDFColors.muted)
        .textCase(.uppercase)
        .padding(.horizontal, 8)
        .frame(height: ExpenseArchivePDF.rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(PDFColors.outline).frame(height: 1) }
    }

    private func row(_ item: ExpenseArchiveSnapshot.Item, striped: Bool) -> some View {
        HStack(spacing: 8) {
            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(PDFColors.muted)
                .frame(width: dateWidth, alignment: .leading)
            HStack(spacing: 4) {
                Text(item.name).foregroundStyle(PDFColors.ink)
                if !item.categories.isEmpty {
                    Text(item.categoryNames.joined(separator: ", "))
                        .foregroundStyle(PDFColors.muted)
                        .font(.system(size: 8.5))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.personName)
                .foregroundStyle(PDFColors.ink)
                .lineLimit(1)
                .frame(width: personWidth, alignment: .leading)
            Text((item.isIncome ? "+" : "-") + item.amount.formattedEuros)
                .fontWeight(.semibold)
                .foregroundStyle(item.isIncome ? Color(hex: 0x2E9C7A) : PDFColors.ink)
                .frame(width: amountWidth, alignment: .trailing)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 8)
        .frame(height: ExpenseArchivePDF.rowHeight)
        .background(striped ? PDFColors.stripe : Color.clear)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Generated with Aliaro · \(Date.now.formatted(date: .abbreviated, time: .omitted))")
            Spacer()
            Text("Page \(pageIndex + 1) of \(pageCount)")
        }
        .font(.system(size: 8.5))
        .foregroundStyle(PDFColors.muted)
        .padding(.horizontal, ExpenseArchivePDF.margin)
        .padding(.bottom, ExpenseArchivePDF.margin - 8)
        .frame(height: ExpenseArchivePDF.footerHeight + ExpenseArchivePDF.margin - 8, alignment: .bottom)
    }
}
