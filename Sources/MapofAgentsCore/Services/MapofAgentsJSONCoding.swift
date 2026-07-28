import Foundation

public enum MapofAgentsJSONCoding {
    /// Shared graph and persistence writers preserve sub-second precision while
    /// normalizing dates to RFC 3339 UTC strings.
    public static func configureContractDates(on encoder: JSONEncoder) {
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
    }

    public static func configureContractDates(on decoder: JSONDecoder) {
        decoder.dateDecodingStrategy = .iso8601
    }
}
