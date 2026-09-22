import SwiftUI

// MARK: - Картка

/// Базовий контейнер: біла поверхня, радіус 16, м'яка тінь.
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.lg
    var elevated: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
            .cardShadow(elevated: elevated)
    }
}

// MARK: - Плитка іконки

struct IconTile: View {
    let symbol: String
    let tint: CategoryTint
    var size: CGFloat = Metrics.iconTile

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous)
            .fill(tint.background)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(tint.foreground)
            )
    }
}

// MARK: - Заголовок секції

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(Typo.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "chevron.right")
                        .font(Typo.caption.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Прогрес бюджету

/// Тонка смуга з заокругленими кінцями. Колір міняється при перевитраті —
/// це єдиний випадок, коли в інтерфейсі з'являється червоний.
struct BudgetBar: View {
    let spent: Decimal
    let limit: Decimal
    var height: CGFloat = Metrics.sm

    private var ratio: Double {
        guard limit > 0 else { return 0 }
        return min(NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: limit).doubleValue, 1)
    }

    private var barColor: Color {
        switch ratio {
        case ..<0.75: return Palette.accent
        case ..<1:    return Palette.warning
        default:      return Palette.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.separator)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(geo.size.width * ratio, height))
                        .animation(.easeOut(duration: 0.35), value: ratio)
                }
            }
            .frame(height: height)

            HStack {
                Text("Бюджет: \(Money.string(limit))")
                Spacer()
                Text("\(Int(ratio * 100))%")
            }
            .font(Typo.caption)
            .foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Компактна плитка категорії

struct CategorySummaryTile: View {
    let symbol: String
    let tint: CategoryTint
    let title: String
    let amount: Decimal

    var body: some View {
        VStack(spacing: Metrics.sm) {
            IconTile(symbol: symbol, tint: tint, size: Metrics.iconTileCompact)
            Text(title)
                .font(Typo.tileLabel)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Text(Money.string(amount))
                .font(Typo.tileAmount)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Рядок операції

struct TransactionRow: View {
    let symbol: String
    let tint: CategoryTint
    let title: String
    let subtitle: String
    let amount: Decimal
    var isIncome: Bool = false
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: Metrics.md) {
            IconTile(symbol: symbol, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(subtitle)
                    .font(Typo.rowSubtitle)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: Metrics.sm)

            Text(isIncome ? "+\(Money.string(amount))" : Money.string(amount))
                .font(Typo.amountRow)
                .foregroundStyle(isIncome ? Palette.income : Palette.expense)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(Typo.caption.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(minHeight: Metrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

// MARK: - Універсальний рядок зі стрілкою

struct DisclosureRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Metrics.md) {
            leading
            Spacer(minLength: Metrics.sm)
            trailing
            Image(systemName: "chevron.right")
                .font(Typo.caption.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(minHeight: Metrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

// MARK: - Роздільник, вирівняний по тексту

struct InsetSeparator: View {
    var leadingInset: CGFloat = Metrics.iconTile + Metrics.md

    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Кнопки

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(
                configuration.isPressed ? Palette.accentPressed : Palette.accent,
                in: RoundedRectangle(cornerRadius: Metrics.radiusButton, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NeutralButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.button)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(
                Palette.surfaceMuted.opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: Metrics.radiusButton, style: .continuous)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Світло-зелена кнопка: додавання категорії, необов'язкові дії.
struct SoftAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.button)
            .foregroundStyle(Palette.onAccentSoft)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(
                Palette.accentSoft.opacity(configuration.isPressed ? 0.75 : 1),
                in: RoundedRectangle(cornerRadius: Metrics.radiusButton, style: .continuous)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Плаваюча кнопка

struct FloatingAddButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(Typo.screenTitle)
                .foregroundStyle(.white)
                .frame(width: Metrics.fabSize, height: Metrics.fabSize)
                .background(Palette.accent, in: Circle())
                .overlay(Circle().stroke(Palette.background, lineWidth: Metrics.xs))
                .shadow(color: Palette.accent.opacity(0.35), radius: Metrics.md, x: 0, y: Metrics.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Добавить расход")
    }
}

// MARK: - Перемикач способу вводу

struct InputModeOption: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    var isEnabled: Bool = true
}

/// Три картки в ряд; вибрана отримує зелений тінт і обведення.
struct InputModePicker: View {
    let options: [InputModeOption]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: Metrics.md) {
            ForEach(options) { option in
                let isSelected = option.id == selection
                Button {
                    guard option.isEnabled else { return }
                    withAnimation(.easeOut(duration: 0.18)) { selection = option.id }
                } label: {
                    VStack(spacing: Metrics.sm) {
                        Image(systemName: option.symbol)
                            .font(Typo.navTitle)
                        Text(option.title)
                            .font(Typo.rowSubtitle)
                    }
                    .foregroundStyle(isSelected ? Palette.onAccentSoft : Palette.textSecondary)
                    .opacity(option.isEnabled ? 1 : 0.4)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.inputModeCard)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.radiusButton, style: .continuous)
                            .fill(isSelected ? Palette.accentSoft : Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radiusButton, style: .continuous)
                            .stroke(isSelected ? Palette.accent.opacity(0.45) : Palette.separator, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Чіп категорії

struct CategoryChip: View {
    let symbol: String
    let tint: CategoryTint
    let title: String

    var body: some View {
        HStack(spacing: Metrics.sm) {
            Image(systemName: symbol)
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(tint.foreground)
            Text(title)
                .font(Typo.rowSubtitle)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Metrics.md)
        .padding(.vertical, Metrics.sm)
        .background(tint.background, in: Capsule())
    }
}

// MARK: - Бейдж стану

struct StatusBadge: View {
    let text: String
    var symbol: String = "sparkles"

    var body: some View {
        HStack(spacing: Metrics.xs) {
            Image(systemName: symbol)
                .font(Typo.caption.weight(.semibold))
            Text(text)
                .font(Typo.caption.weight(.medium))
        }
        .foregroundStyle(Palette.onAccentSoft)
        .padding(.horizontal, Metrics.sm)
        .padding(.vertical, Metrics.xs)
        .background(Palette.accentSoft, in: Capsule())
    }
}

// MARK: - Декоративна хвиля запису

struct WaveformView: View {
    var isActive: Bool = false
    var audioLevel: CGFloat = 0.45

    private let shape: [CGFloat] = [
        0.22, 0.38, 0.52, 0.34, 0.68, 0.90, 0.58, 0.82, 1.00, 0.72,
        0.94, 0.54, 0.78, 0.42, 0.64, 0.36, 0.50, 0.28, 0.40, 0.24
    ]

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.xs) {
            ForEach(Array(shape.enumerated()), id: \.offset) { _, level in
                let height = max(Metrics.sm, Metrics.fabSize * level * (isActive ? audioLevel : 0.35))
                Capsule()
                    .fill(isActive ? Palette.accent : Palette.accent.opacity(0.45))
                    .frame(width: Metrics.xs, height: height)
            }
        }
        .frame(height: Metrics.fabSize)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.12), value: audioLevel)
        .accessibilityHidden(true)
    }
}

// MARK: - Плейсхолдер чека

struct ReceiptPlaceholder: View {
    private let lines: [(String, Decimal)] = [
        ("Bananen", Decimal(string: "1.72")!),
        ("Joghurt", Decimal(string: "1.49")!),
        ("Brot", Decimal(string: "1.89")!),
        ("Tomaten", Decimal(string: "1.29")!),
        ("Käse", Decimal(string: "3.49")!),
        ("Mineralwasser", Decimal(string: "3.99")!)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text("REWE")
                .font(Typo.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity)

            Text("REWE Markt GmbH")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)

            VStack(spacing: Metrics.xs) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Text(line.0)
                        Spacer()
                        Text(Money.string(line.1))
                            .monospacedDigit()
                    }
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.top, Metrics.sm)
        }
        .padding(Metrics.lg)
        .frame(maxWidth: .infinity)
        .background(
            Palette.surfaceMuted,
            in: RoundedRectangle(cornerRadius: Metrics.radiusChip, style: .continuous)
        )
    }
}
