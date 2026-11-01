import Foundation

/// Everyday colour names the phone can suggest. The app translates them.
public enum ColourName: String, Sendable, CaseIterable {
    case black, charcoal, grey, white, cream, beige, camel, brown, navy, blue, lightBlue
    case green, olive, red, burgundy, pink, orange, yellow, purple
}

/// Kinds of clothing the phone can recognise in a photo. The app translates them.
public enum ClothingCategory: String, Sendable, CaseIterable {
    case jacket, coat, suit, shirt, tshirt, knitwear, sweatshirt, jeans, trousers, shorts
    case shoes, boots, hat, scarf, accessory, bag
}

/// The dominant colours of a cut-out, measured on the phone. They describe the photo, not the
/// fabric's true colour, so the colour tag they suggest stays a suggestion.
public enum Swatches {
    /// `rgba` holds 8-bit RGBA pixels. Transparent pixels (the cut-out's background) are skipped,
    /// and a colour must cover at least a tenth of the piece to count.
    public static func dominant(rgba: [UInt8], limit: Int = 3) -> [Swatch] {
        var buckets: [Int: Bucket] = [:]
        var opaque = 0
        var index = 0
        while index + 3 < rgba.count {
            if rgba[index + 3] >= 250 {
                let red = Int(rgba[index]), green = Int(rgba[index + 1]), blue = Int(rgba[index + 2])
                // Eight levels per channel: close shades share a bucket.
                let key = (red >> 5) << 6 | (green >> 5) << 3 | blue >> 5
                buckets[key, default: Bucket()].add(red, green, blue)
                opaque += 1
            }
            index += 4
        }
        guard opaque > 0 else { return [] }
        return buckets
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            .map(\.value)
            .filter { $0.count * 10 >= opaque }
            .prefix(limit)
            .map { Swatch(hex: $0.hex) }
    }

    /// The nearest everyday colour name, for the colour tag the phone suggests.
    public static func nearestName(hex: String) -> ColourName? {
        guard let rgb = components(hex) else { return nil }
        return names.min { distance($0, rgb) < distance($1, rgb) }?.key
    }

    private struct Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        mutating func add(_ red: Int, _ green: Int, _ blue: Int) {
            count += 1
            self.red += red
            self.green += green
            self.blue += blue
        }

        var hex: String {
            "#" + [red, green, blue].map { total in
                let digits = String(total / count, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
        }
    }

    private struct Named {
        let key: ColourName
        let red: Int
        let green: Int
        let blue: Int
    }

    private static let names: [Named] = [
        Named(key: .black, red: 22, green: 22, blue: 24),
        Named(key: .charcoal, red: 58, green: 60, blue: 64),
        Named(key: .grey, red: 128, green: 128, blue: 128),
        Named(key: .white, red: 246, green: 246, blue: 242),
        Named(key: .cream, red: 236, green: 226, blue: 200),
        Named(key: .beige, red: 200, green: 180, blue: 150),
        Named(key: .camel, red: 188, green: 143, blue: 92),
        Named(key: .brown, red: 105, green: 70, blue: 45),
        Named(key: .navy, red: 31, green: 42, blue: 68),
        Named(key: .blue, red: 50, green: 90, blue: 170),
        Named(key: .lightBlue, red: 150, green: 185, blue: 220),
        Named(key: .green, red: 50, green: 120, blue: 60),
        Named(key: .olive, red: 107, green: 107, blue: 52),
        Named(key: .red, red: 180, green: 35, blue: 40),
        Named(key: .burgundy, red: 98, green: 26, blue: 40),
        Named(key: .pink, red: 230, green: 165, blue: 180),
        Named(key: .orange, red: 225, green: 120, blue: 45),
        Named(key: .yellow, red: 232, green: 200, blue: 70),
        Named(key: .purple, red: 100, green: 60, blue: 130),
    ]

    private static func components(_ hex: String) -> [Int]? {
        guard hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return [value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff]
    }

    /// Weighted RGB distance: crude, but enough to name a colour.
    private static func distance(_ named: Named, _ rgb: [Int]) -> Int {
        let dr = named.red - rgb[0], dg = named.green - rgb[1], db = named.blue - rgb[2]
        return 2 * dr * dr + 4 * dg * dg + 3 * db * db
    }
}
