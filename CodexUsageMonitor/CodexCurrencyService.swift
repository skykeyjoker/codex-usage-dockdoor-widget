import Foundation
import SwiftUI

enum CodexCurrency: String, CaseIterable, Codable, Identifiable, Sendable {
    case usd = "USD"
    case cny = "CNY"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case hkd = "HKD"
    case krw = "KRW"
    case cad = "CAD"
    case aud = "AUD"
    case sgd = "SGD"
    case chf = "CHF"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usd: CodexLocalization.text("美元 (USD)", "US Dollar (USD)")
        case .cny: CodexLocalization.text("人民币 (CNY)", "Chinese Yuan (CNY)")
        case .eur: CodexLocalization.text("欧元 (EUR)", "Euro (EUR)")
        case .gbp: CodexLocalization.text("英镑 (GBP)", "British Pound (GBP)")
        case .jpy: CodexLocalization.text("日元 (JPY)", "Japanese Yen (JPY)")
        case .hkd: CodexLocalization.text("港币 (HKD)", "Hong Kong Dollar (HKD)")
        case .krw: CodexLocalization.text("韩元 (KRW)", "South Korean Won (KRW)")
        case .cad: CodexLocalization.text("加拿大元 (CAD)", "Canadian Dollar (CAD)")
        case .aud: CodexLocalization.text("澳大利亚元 (AUD)", "Australian Dollar (AUD)")
        case .sgd: CodexLocalization.text("新加坡元 (SGD)", "Singapore Dollar (SGD)")
        case .chf: CodexLocalization.text("瑞士法郎 (CHF)", "Swiss Franc (CHF)")
        }
    }

    static func resolve(title: String) -> CodexCurrency {
        allCases.first { title == $0.rawValue || title == $0.title } ?? .usd
    }
}

struct CodexExchangeRateSnapshot: Codable, Equatable, Sendable {
    let ratesPerEUR: [String: Double]
    let publishedDate: String
    let fetchedAt: Date
    let sourceURL: String

    func usdMultiplier(to currency: CodexCurrency) -> Double? {
        if currency == .usd { return 1 }
        guard let usdPerEUR = ratesPerEUR[CodexCurrency.usd.rawValue],
              usdPerEUR.isFinite,
              usdPerEUR > 0
        else { return nil }
        let targetPerEUR = currency == .eur ? 1 : ratesPerEUR[currency.rawValue]
        guard let targetPerEUR, targetPerEUR.isFinite, targetPerEUR > 0 else { return nil }
        return targetPerEUR / usdPerEUR
    }
}

struct CodexCurrencyContext: Equatable {
    let currency: CodexCurrency
    let exchangeRates: CodexExchangeRateSnapshot?

    static let usd = CodexCurrencyContext(currency: .usd, exchangeRates: nil)

    var effectiveCurrency: CodexCurrency {
        currency == .usd || exchangeRates?.usdMultiplier(to: currency) != nil
            ? currency
            : .usd
    }

    func convertedUSD(_ value: Double) -> Double {
        guard currency != .usd,
              let multiplier = exchangeRates?.usdMultiplier(to: currency)
        else { return value }
        return value * multiplier
    }

    func formatUSD(_ value: Double, compact: Bool = false) -> String {
        let effectiveCurrency = effectiveCurrency
        let converted = effectiveCurrency == currency ? convertedUSD(value) : value
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = effectiveCurrency.rawValue
        formatter.locale = Locale(identifier: "en_US")
        formatter.usesGroupingSeparator = true
        let zeroFraction = effectiveCurrency == .jpy || effectiveCurrency == .krw
        if zeroFraction || compact {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: converted))
            ?? "\(effectiveCurrency.rawValue) \(converted)"
    }
}

private struct CodexCurrencyContextKey: EnvironmentKey {
    static let defaultValue = CodexCurrencyContext.usd
}

extension EnvironmentValues {
    var codexCurrencyContext: CodexCurrencyContext {
        get { self[CodexCurrencyContextKey.self] }
        set { self[CodexCurrencyContextKey.self] = newValue }
    }
}

struct CodexCurrencyService: Sendable {
    static let sourceURLString = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(now: Date = Date()) async throws -> CodexExchangeRateSnapshot {
        guard let url = URL(string: Self.sourceURLString) else {
            throw CodexCurrencyError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/xml,text/xml", forHTTPHeaderField: "Accept")
        request.setValue(
            "CodexUsageDockDoorWidget/\(CodexReleaseUpdateService.currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CodexCurrencyError.invalidResponse
        }

        let delegate = CodexECBRateParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(),
              let publishedDate = delegate.publishedDate,
              let usdRate = delegate.rates[CodexCurrency.usd.rawValue],
              usdRate > 0
        else {
            throw CodexCurrencyError.parseFailed(
                parser.parserError?.localizedDescription ?? "missing daily rates"
            )
        }

        var supportedRates = [CodexCurrency.eur.rawValue: 1.0]
        for currency in CodexCurrency.allCases where currency != .eur {
            if let rate = delegate.rates[currency.rawValue], rate.isFinite, rate > 0 {
                supportedRates[currency.rawValue] = rate
            }
        }
        return CodexExchangeRateSnapshot(
            ratesPerEUR: supportedRates,
            publishedDate: publishedDate,
            fetchedAt: now,
            sourceURL: Self.sourceURLString
        )
    }
}

private final class CodexECBRateParserDelegate: NSObject, XMLParserDelegate {
    var publishedDate: String?
    var rates: [String: Double] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "Cube" else { return }
        if let time = attributeDict["time"], !time.isEmpty {
            publishedDate = time
        }
        if let currency = attributeDict["currency"]?.uppercased(),
           let rawRate = attributeDict["rate"],
           let rate = Double(rawRate),
           rate.isFinite,
           rate > 0
        {
            rates[currency] = rate
        }
    }
}

enum CodexCurrencyError: LocalizedError {
    case invalidResponse
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            CodexLocalization.text("欧洲央行汇率响应无效", "The ECB exchange-rate response was invalid.")
        case let .parseFailed(message):
            CodexLocalization.text(
                "无法解析欧洲央行汇率：\(message)",
                "Unable to parse ECB exchange rates: \(message)"
            )
        }
    }
}
