import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddExpenseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var mode = "text"
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var drafts: [ExpenseDraft] = []
    @State private var clarificationQuestion: String?
    @State private var showingReview = false
    @State private var isRecognizing = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cameraImage: UIImage?
    @State private var showingCamera = false
    @State private var receiptPreview: UIImage?
    @StateObject private var speech = SpeechRecognizer()

    private let modes = [
        InputModeOption(id: "text", symbol: "doc.text", title: "Текст"),
        InputModeOption(id: "voice", symbol: "mic.fill", title: "Голос"),
        InputModeOption(id: "receipt", symbol: "camera.fill", title: "Чек")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                VStack(spacing: Metrics.lg) {
                    noteCard
                    if let hint = liveHint {
                        Text(hint)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Распознано: \(hint)")
                    }
                    InputModePicker(options: modes, selection: $mode)

                    Spacer()

                    switch mode {
                    case "voice":
                        voicePanel
                    case "receipt":
                        receiptPanel
                    default:
                        caption("Введите расход своими словами")
                    }

                    Spacer()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Typo.caption)
                            .foregroundStyle(Palette.danger)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityLabel("Ошибка: \(errorMessage)")
                    }

                    Button(isRecognizing ? "Распознаю…" : "Распознать") {
                        recognize()
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !isRecognizing))
                    .disabled(isRecognizing)
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.vertical, Metrics.lg)
            }
            .navigationTitle("Добавить")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        speech.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(Typo.navTitle)
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .accessibilityLabel("Назад")
                }
            }
            .toolbarBackground(Palette.background, for: .navigationBar)
            .navigationDestination(isPresented: $showingReview) {
                if !drafts.isEmpty {
                    ReviewScreen(
                        drafts: drafts,
                        clarificationQuestion: clarificationQuestion
                    ) {
                        dismiss()
                    } onFix: {
                        showingReview = false
                    }
                }
            }
            .onChange(of: speech.transcript) { _, value in
                if !value.isEmpty { note = value }
            }
            .onChange(of: speech.errorMessage) { _, value in
                errorMessage = value
            }
            .onChange(of: mode) { _, newMode in
                errorMessage = nil
                if newMode != "voice" { speech.stop() }
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
            .onChange(of: cameraImage) { _, image in
                receiptPreview = image
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("autoParseTest"), note.isEmpty, !isRecognizing {
                    note = "кофе 80, метро 20"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        recognize()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: $cameraImage)
                    .ignoresSafeArea()
            }
        }
        .tint(Palette.accent)
    }

    private var noteCard: some View {
        Card(padding: Metrics.lg) {
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Сегодня потратил 12 € в REWE")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textTertiary)
                }
                TextEditor(text: $note)
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: Metrics.xxl * 3, maxHeight: Metrics.fabSize * 2, alignment: .topLeading)
            }
        }
    }

    private var voicePanel: some View {
        VStack(spacing: Metrics.lg) {
            WaveformView(isActive: speech.isListening, audioLevel: speech.audioLevel)

            VStack(spacing: Metrics.md) {
                Button {
                    speech.toggle()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(Typo.screenTitle)
                        .foregroundStyle(speech.isListening ? .white : Palette.onAccentSoft)
                        .frame(width: Metrics.micButton, height: Metrics.micButton)
                        .background(speech.isListening ? Palette.accent : Palette.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isListening ? "Остановить запись" : "Начать диктовку")
                .accessibilityAddTraits(speech.isListening ? .isSelected : [])

                Text(speech.isListening ? "Слушаю…" : "Нажмите, чтобы диктовать")
                    .font(Typo.rowSubtitle)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var receiptPanel: some View {
        VStack(spacing: Metrics.md) {
            if let receiptPreview {
                Image(uiImage: receiptPreview)
                    .resizable()
                    .scaledToFill()
                    .frame(height: Metrics.fabSize * 2)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusChip, style: .continuous))
            }

            HStack(spacing: Metrics.md) {
                Button("Камера") { showingCamera = true }
                    .buttonStyle(NeutralButtonStyle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Фото")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeutralButtonStyle())
            }

            caption("Сфотографируйте чек или выберите снимок")
        }
    }

    private var liveHint: String? {
        let sample = mode == "receipt" ? "" : note
        guard sample.count >= 3 else { return nil }
        return ExpenseParser.preview(sample, categories: FinanceStore.fetchCategories(in: context))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Typo.rowSubtitle)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
    }

    private func recognize() {
        errorMessage = nil
        let categories = FinanceStore.fetchCategories(in: context)

        if mode == "receipt" {
            guard let receiptPreview else {
                errorMessage = "Сначала добавьте фото чека"
                return
            }
            Task {
                let result = await ReceiptScanner.recognize(image: receiptPreview)
                await MainActor.run {
                    switch result {
                    case .success(let scan):
                        applyParse(scan.text, source: .receipt, receipt: scan.data, categories: categories)
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            }
            return
        }

        if mode == "voice" {
            speech.stop()
        }
        applyParse(note, source: mode == "voice" ? .voice : .text, receipt: nil, categories: categories)
    }

    private func applyParse(
        _ text: String,
        source: ExpenseSource,
        receipt: Data?,
        categories: [CategoryEntity]
    ) {
        let snapshots = categories.map(ParserCategory.init)
        let fallbackNote = note
        isRecognizing = true
        Task {
            let parsed = await parseWithAIFallback(
                text,
                source: source,
                receipt: receipt,
                snapshots: snapshots,
                fallbackNote: fallbackNote
            )
            await MainActor.run {
                isRecognizing = false
                switch parsed {
                case .success(let result):
                    drafts = result.drafts
                    clarificationQuestion = result.clarificationQuestion
                    if let first = result.drafts.first, !first.note.isEmpty {
                        note = first.note
                    }
                    showingReview = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func parseWithAIFallback(
        _ text: String,
        source: ExpenseSource,
        receipt: Data?,
        snapshots: [ParserCategory],
        fallbackNote: String
    ) async -> Result<AIParseResult, Error> {
        do {
            var result = try await AIParserClient.parse(text: text, categories: snapshots, source: source)
            if let receipt {
                result.drafts = result.drafts.map { draft in
                    var copy = draft
                    copy.receiptPNG = receipt
                    return copy
                }
            }
            return .success(result)
        } catch {
            return await MainActor.run {
                let categories = FinanceStore.fetchCategories(in: context)
                switch ExpenseParser.parse(text, categories: categories, source: source) {
                case .success(var parsed):
                    parsed.receiptPNG = receipt
                    if parsed.note.isEmpty { parsed.note = fallbackNote }
                    return .success(AIParseResult(drafts: [parsed], needsConfirmation: true, clarificationQuestion: nil, provider: "local"))
                case .failure:
                    return .failure(AIParserError.from(error))
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await MainActor.run { receiptPreview = image }
    }
}

#Preview("Добавить") {
    AddExpenseScreen()
        .modelContainer(FinanceStore.previewContainer)
}
