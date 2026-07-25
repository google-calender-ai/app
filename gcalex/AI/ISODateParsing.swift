import Foundation

enum ISODateParsingError: Error, Equatable {
    case invalidFormat(date: String, time: String)
}

enum ISODateParsing {
    static func combine(date: String, time: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let result = formatter.date(from: "\(date) \(time)") else {
            throw ISODateParsingError.invalidFormat(date: date, time: time)
        }
        return result
    }
}
