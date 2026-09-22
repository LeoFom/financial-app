import SwiftUI

// MARK: - Hex helpers

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// Динамічний колір: автоматично перемикається між світлою і темною темою.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

// MARK: - Палітра

enum Palette {

    // Акцент — знято з референсу (#1D7150). У темній темі підсвітлюємо,
    // бо насичений темно-зелений на чорному втрачає читабельність.
    static let accent        = adaptive(0x1D7150, 0x35A272)
    static let accentPressed = adaptive(0x165B40, 0x2B8A60)
    /// Світлий тінт акценту: вибрані стани, другорядні дії, чіпи.
    static let accentSoft    = adaptive(0xE7F4EB, 0x14322A)
    /// Текст/іконка поверх accentSoft.
    static let onAccentSoft  = adaptive(0x1D7150, 0x5FC79A)

    // База
    static let background    = adaptive(0xF4F4F2, 0x0E0E10)
    static let surface       = adaptive(0xFFFFFF, 0x1C1C1E)
    /// Другий рівень поверхні — поля вводу, нейтральні кнопки.
    static let surfaceMuted  = adaptive(0xF1F1EF, 0x2A2A2D)
    static let separator     = adaptive(0xE9E9E6, 0x2E2E31)

    // Текст
    static let textPrimary   = adaptive(0x141414, 0xF5F5F7)
    static let textSecondary = adaptive(0x8A8A8E, 0x98989F)
    static let textTertiary  = adaptive(0xB0B0B4, 0x6C6C70)

    // Семантика сум
    static let expense       = adaptive(0x141414, 0xF5F5F7)
    static let income        = adaptive(0x1D7150, 0x35A272)
    static let warning       = adaptive(0xE2A020, 0xF0B845)
    static let danger        = adaptive(0xD9503F, 0xF07A6A)
}

// MARK: - Кольори категорій

/// Кожна категорія — насичена іконка на власній пастельній плитці.
enum CategoryTint: String, CaseIterable, Identifiable {
    case green, blue, purple, coral, amber, teal

    var id: String { rawValue }

    /// Колір символа.
    var foreground: Color {
        switch self {
        case .green:  return .adaptive(light: 0x3AA06E, dark: 0x4FBF87)
        case .blue:   return .adaptive(light: 0x3D7FD1, dark: 0x5C9BEA)
        case .purple: return .adaptive(light: 0x9166D8, dark: 0xAE8BEC)
        case .coral:  return .adaptive(light: 0xEE6F5E, dark: 0xF58B7B)
        case .amber:  return .adaptive(light: 0xDD921D, dark: 0xF0AF45)
        case .teal:   return .adaptive(light: 0x2E9AA0, dark: 0x4FBAC0)
        }
    }

    /// Підкладка плитки.
    var background: Color {
        switch self {
        case .green:  return .adaptive(light: 0xE6F4EC, dark: 0x163024)
        case .blue:   return .adaptive(light: 0xE6EFFA, dark: 0x14243A)
        case .purple: return .adaptive(light: 0xF0E9FC, dark: 0x241A38)
        case .coral:  return .adaptive(light: 0xFDEAE6, dark: 0x381E1A)
        case .amber:  return .adaptive(light: 0xFCF2DC, dark: 0x352713)
        case .teal:   return .adaptive(light: 0xE2F3F4, dark: 0x122E30)
        }
    }
}

private extension Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color.adaptive(light: light, dark: dark)
    }
}

// MARK: - Типографіка

/// Шкала побудована на SF Pro. Заголовок екрана навмисно важчий за решту —
/// це єдине місце, де тексту дозволено домінувати.
enum Typo {
    static let screenTitle = Font.system(size: 28, weight: .bold)
    static let navTitle    = Font.system(size: 17, weight: .semibold)
    static let body        = Font.system(size: 17, weight: .regular)

    /// Велика сума на головній картці.
    static let amountHero  = Font.system(size: 34, weight: .bold).monospacedDigit()
    /// Сума в рядку операції.
    static let amountRow   = Font.system(size: 15, weight: .semibold).monospacedDigit()

    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let rowTitle     = Font.system(size: 16, weight: .medium)
    static let rowSubtitle  = Font.system(size: 13, weight: .regular)
    static let button       = Font.system(size: 16, weight: .semibold)
    static let caption      = Font.system(size: 12, weight: .regular)
    static let tileLabel    = Font.system(size: 11, weight: .medium)
    static let tileAmount   = Font.system(size: 12, weight: .semibold).monospacedDigit()
}

// MARK: - Метрики

enum Metrics {
    // Відступи, крок 4
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24

    /// Поля екрана.
    static let screenInset: CGFloat = 16

    // Радіуси — різні за ієрархією, не один на все
    static let radiusCard: CGFloat = 16
    static let radiusButton: CGFloat = 14
    static let radiusTile: CGFloat = 10
    static let radiusChip: CGFloat = 8

    // Розміри
    static let iconTile: CGFloat = 36
    static let iconTileLarge: CGFloat = 40
    static let iconTileCompact: CGFloat = 32
    static let buttonHeight: CGFloat = 50
    static let rowMinHeight: CGFloat = 52
    static let fabSize: CGFloat = 56
    static let inputModeCard: CGFloat = 72
    static let micButton: CGFloat = 64
    static let navPlus: CGFloat = 28
}

// MARK: - Тінь

/// Свідомо ледь помітна: дві м'які тіні замість однієї сірої плями.
struct CardShadow: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(elevated ? 0.08 : 0.04),
                    radius: elevated ? 16 : 8,
                    x: 0, y: elevated ? 6 : 2)
            .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func cardShadow(elevated: Bool = false) -> some View {
        modifier(CardShadow(elevated: elevated))
    }
}

// MARK: - Форматування грошей

enum Money {
    static func string(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.currencySymbol = "€"
        formatter.positiveFormat = "#,##0.00 ¤"
        formatter.negativeFormat = "-#,##0.00 ¤"
        formatter.groupingSeparator = "\u{00A0}"
        formatter.decimalSeparator = ","
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    static func parse(_ raw: String) -> Decimal? {
        let cleaned = raw
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "евро", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned) else { return nil }
        return value
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
