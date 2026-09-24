import Foundation

public enum TextDecoding {
    /// Decodes file bytes to a String. Tries UTF-8 (the overwhelmingly common case) first,
    /// honours UTF-16/32 byte-order marks, then lets Foundation guess legacy encodings.
    /// Returns nil when the data looks binary.
    public static func decode(_ data: Data) -> String? {
        if data.isEmpty { return "" }

        let boms: [([UInt8], String.Encoding)] = [
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian),
            ([0xFE, 0xFF], .utf16BigEndian),
        ]
        for (bom, encoding) in boms where data.starts(with: bom) {
            return String(data: data.dropFirst(bom.count), encoding: encoding)
        }

        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }

        // NUL bytes in the first few KB almost always mean a binary file.
        if data.prefix(8192).contains(0) { return nil }

        var converted: NSString?
        let encoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [.suggestedEncodingsKey: [String.Encoding.windowsCP1252.rawValue,
                                                       String.Encoding.macOSRoman.rawValue]],
            convertedString: &converted,
            usedLossyConversion: nil
        )
        if encoding != 0, let converted { return converted as String }
        return String(decoding: data, as: UTF8.self)
    }
}
