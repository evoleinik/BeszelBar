import AppKit

/// Pixel fonts drawn one point per pixel on the pixel grid with antialiasing off, so tiny labels
/// stay sharp. Uppercase letters, digits, '-' and '.'; anything else draws as a space.
/// `PixelFont` is the 3×5 face; `PixelFont7` is the more readable 5×7 face.
enum PixelFont7 {
    static let width = 5
    static let height = 7
    static let advance = 6
    static let glyphs: [Character: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
    ]

    static func pixels(_ text: String) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (index, char) in text.uppercased().enumerated() {
            guard let rows = glyphs[char] else { continue }
            for (row, line) in rows.enumerated() {
                for (col, cell) in line.enumerated() where cell == "#" {
                    out.append((index * advance + col, row))
                }
            }
        }
        return out
    }

    static func length(_ count: Int) -> Int { max(0, count * advance - 1) }

    /// `text` upright, top-left corner at (left, top) in points, cut to fit `maxWidth`.
    static func topLeftPoints(_ text: String, left: CGFloat, top: CGFloat, maxWidth: CGFloat) -> [(Int, Int)] {
        let shown = String(text.prefix(max(0, (Int(maxWidth) + 1) / advance)))
        let x0 = Int(left.rounded(.up))
        let yTop = Int(top.rounded(.down)) - 1
        return pixels(shown).map { col, row in (x0 + col, yTop - row) }
    }

    /// `text` upright, top-right corner at (right, top) in points.
    static func topRightPoints(_ text: String, right: CGFloat, top: CGFloat) -> [(Int, Int)] {
        let x0 = Int(right.rounded(.down)) - length(text.count)
        let yTop = Int(top.rounded(.down)) - 1
        return pixels(text).map { col, row in (x0 + col, yTop - row) }
    }
}

enum PixelFont {
    static let width = 3
    static let height = 5
    static let advance = 4  // glyph width plus one blank column

    // Rows top to bottom, "#" lit.
    static let glyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
        "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
        "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
        "W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
        "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
        "-": ["...", "...", "###", "...", "..."], ".": ["...", "...", "...", "...", ".#."],
    ]

    /// Lit pixels of `text` laid out left to right, as (column, row-from-top).
    static func pixels(_ text: String) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (index, char) in text.uppercased().enumerated() {
            guard let rows = glyphs[char] else { continue }
            for (row, line) in rows.enumerated() {
                for (col, cell) in line.enumerated() where cell == "#" {
                    out.append((index * advance + col, row))
                }
            }
        }
        return out
    }

    /// Length in points of `count` characters.
    static func length(_ count: Int) -> Int { max(0, count * advance - 1) }

    /// How many characters fit in `points`.
    static func fits(_ points: CGFloat) -> Int { max(0, (Int(points) + 1) / advance) }

    /// Draws `points` (already placed, in whole points) as light pixels with a one-pixel dark
    /// outline, with antialiasing off.
    static func draw(_ points: [(Int, Int)], light: NSColor, outline: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        let lit = Set(points.map { "\($0.0),\($0.1)" })
        outline.setFill()
        var halo = Set<String>()
        for (x, y) in points {
            for dx in -1...1 {
                for dy in -1...1 {
                    let key = "\(x + dx),\(y + dy)"
                    if !lit.contains(key) && halo.insert(key).inserted {
                        NSRect(x: x + dx, y: y + dy, width: 1, height: 1).fill()
                    }
                }
            }
        }
        light.setFill()
        for (x, y) in points {
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// `text` reading bottom to top along a box's inside left edge: letter tops face left and sit
    /// `inset` points in from `left`. Truncated to what fits `height`, centred on `midY`.
    static func verticalPoints(_ text: String, left: CGFloat, midY: CGFloat, height: CGFloat,
                               inset: Int) -> [(Int, Int)] {
        let shown = String(text.prefix(fits(height - 2)))
        let start = Int((midY - CGFloat(length(shown.count)) / 2).rounded(.down))
        let x0 = Int(left.rounded(.up)) + inset
        // Turned a quarter turn anticlockwise: a glyph's column runs up, its top row is leftmost.
        return pixels(shown).map { col, row in (x0 + row, start + col) }
    }

    /// `text` upright with its top-right corner at (right, top), both in points.
    static func cornerPoints(_ text: String, right: CGFloat, top: CGFloat) -> [(Int, Int)] {
        let x0 = Int(right.rounded(.down)) - length(text.count)
        let yTop = Int(top.rounded(.down)) - 1
        return pixels(text).map { col, row in (x0 + col, yTop - row) }
    }
}
