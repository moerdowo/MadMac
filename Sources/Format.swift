import Foundation

// Currency / metric formatting matching the prototype (Indonesian Rp by default;
// "Rp 4,8 jt" compact style). Falls back to plain currency formatting for
// non-IDR accounts.

enum Fmt {
    static var currency: String = "IDR"

    static func money(_ n: Double?, compact: Bool = false) -> String {
        guard let n else { return "—" }
        if currency == "IDR" { return rp(n, compact: compact) }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = 0
        if compact, abs(n) >= 1000 {
            let sym = f.currencySymbol ?? currency
            if abs(n) >= 1_000_000 {
                return "\(sym)\((n / 1_000_000).formatted(.number.precision(.fractionLength(abs(n) >= 10_000_000 ? 0 : 1))))M"
            }
            return "\(sym)\(Int((n / 1000).rounded()))k"
        }
        return f.string(from: NSNumber(value: n)) ?? "—"
    }

    static func rp(_ n: Double, compact: Bool) -> String {
        let absN = abs(n)
        if compact && absN >= 1_000_000 {
            let v = n / 1_000_000
            let digits = absN >= 10_000_000 ? 0 : 1
            let s = String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
            return "Rp \(s) jt"
        }
        if compact && absN >= 1000 {
            return "Rp \(Int((n / 1000).rounded())) rb"
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.maximumFractionDigits = 0
        return "Rp " + (f.string(from: NSNumber(value: n.rounded())) ?? "0")
    }

    static func int(_ n: Int?) -> String {
        guard let n else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = currency == "IDR" ? "." : ","
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    static func compactInt(_ n: Double) -> String {
        if n >= 1000 {
            let digits = n >= 10000 ? 0 : 1
            let s = String(format: "%.\(digits)f", n / 1000).replacingOccurrences(of: ".", with: ",")
            return "\(s) rb"
        }
        return String(Int(n))
    }

    static func metric(_ v: Double, _ fmt: KpiFormat) -> String {
        switch fmt {
        case .money: return money(v, compact: true)
        case .x: return String(format: "%.2f×", v)
        case .pct: return String(format: "%.2f%%", v)
        case .int: return compactInt(v)
        }
    }

    static func roas(_ v: Double) -> String {
        v > 0 ? String(format: "%.2f×", v) : "—"
    }
}
