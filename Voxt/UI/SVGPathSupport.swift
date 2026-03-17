import SwiftUI
import AppKit

struct SVGPathShape: Shape {
    let pathData: String
    let viewport: CGSize

    init(pathData: String, viewport: CGSize = CGSize(width: 24, height: 24)) {
        self.pathData = pathData
        self.viewport = viewport
    }

    func path(in rect: CGRect) -> Path {
        let path = SVGPathCache.path(for: pathData)
        let transform = CGAffineTransform(
            scaleX: rect.width / max(viewport.width, 1),
            y: rect.height / max(viewport.height, 1)
        )
        return path.applying(transform)
    }
}

enum SVGPathCache {
    private static let lock = NSLock()
    private static var storage: [String: Path] = [:]

    static func path(for pathData: String) -> Path {
        lock.lock()
        if let cached = storage[pathData] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var parser = SVGPathParser(pathData: pathData)
        let parsed = parser.parse()

        lock.lock()
        storage[pathData] = parsed
        lock.unlock()
        return parsed
    }
}

struct SVGPathParser {
    let pathData: String
    private let separators = CharacterSet(charactersIn: " ,\n\t")

    private var characters: [Character] { Array(pathData) }
    private var index = 0

    init(pathData: String) {
        self.pathData = pathData
    }

    mutating func parse() -> Path {
        var path = Path()
        var command: Character?
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero

        while true {
            skipSeparators()
            guard index < characters.count else { break }

            if let nextCommand = currentCommandCharacter() {
                command = nextCommand
                index += 1
            }

            guard let command else { break }

            switch command {
            case "M":
                guard let point = readPoint() else { break }
                path.move(to: point)
                currentPoint = point
                subpathStart = point

                while let point = readPoint() {
                    path.addLine(to: point)
                    currentPoint = point
                }
            case "L":
                while let point = readPoint() {
                    path.addLine(to: point)
                    currentPoint = point
                }
            case "C":
                while let control1 = readPoint(),
                      let control2 = readPoint(),
                      let point = readPoint() {
                    path.addCurve(to: point, control1: control1, control2: control2)
                    currentPoint = point
                }
            case "H":
                while let x = readNumber() {
                    currentPoint = CGPoint(x: x, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                }
            case "V":
                while let y = readNumber() {
                    currentPoint = CGPoint(x: currentPoint.x, y: y)
                    path.addLine(to: currentPoint)
                }
            case "Z", "z":
                path.closeSubpath()
                currentPoint = subpathStart
            default:
                index += 1
            }
        }

        return path
    }

    private mutating func currentCommandCharacter() -> Character? {
        guard index < characters.count else { return nil }
        let character = characters[index]
        return character.isLetter ? character : nil
    }

    private mutating func skipSeparators() {
        while index < characters.count {
            let scalar = String(characters[index]).unicodeScalars.first
            if let scalar, separators.contains(scalar) {
                index += 1
            } else {
                break
            }
        }
    }

    private mutating func readPoint() -> CGPoint? {
        let startIndex = index
        guard let x = readNumber() else {
            index = startIndex
            return nil
        }
        guard let y = readNumber() else {
            index = startIndex
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    private mutating func readNumber() -> CGFloat? {
        skipSeparators()
        guard index < characters.count else { return nil }

        let start = index
        var hasDigit = false

        if characters[index] == "-" || characters[index] == "+" {
            index += 1
        }

        while index < characters.count, characters[index].isNumber {
            hasDigit = true
            index += 1
        }

        if index < characters.count, characters[index] == "." {
            index += 1
            while index < characters.count, characters[index].isNumber {
                hasDigit = true
                index += 1
            }
        }

        guard hasDigit else {
            index = start
            return nil
        }

        let numberString = String(characters[start..<index])
        return CGFloat(Double(numberString) ?? 0)
    }
}
