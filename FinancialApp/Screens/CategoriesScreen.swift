import SwiftData
import SwiftUI

struct CategoriesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CategoryEntity.sortOrder) private var items: [CategoryEntity]
    @State private var editor: CategoryEditorItem?

    private var visible: [CategoryEntity] {
        items.filter { !$0.isArchived }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Metrics.md) {
                    ForEach(visible, id: \.stableID) { item in
                        Button {
                            editor = CategoryEditorItem(category: item)
                        } label: {
                            Card(padding: Metrics.md) {
                                DisclosureRow {
                                    HStack(spacing: Metrics.md) {
                                        IconTile(symbol: item.symbol, tint: item.tint)
                                        Text(item.title)
                                            .font(Typo.rowTitle)
                                            .foregroundStyle(Palette.textPrimary)
                                    }
                                } trailing: {
                                    EmptyView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        editor = CategoryEditorItem(category: nil)
                    } label: {
                        Label("Добавить категорию", systemImage: "plus")
                    }
                    .buttonStyle(SoftAccentButtonStyle())
                    .padding(.top, Metrics.xs)
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.vertical, Metrics.sm)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Категории")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = CategoryEditorItem(category: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(Typo.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: Metrics.navPlus, height: Metrics.navPlus)
                        .background(Palette.accent, in: Circle())
                }
                .accessibilityLabel("Добавить категорию")
            }
        }
        .toolbarBackground(Palette.background, for: .navigationBar)
        .sheet(item: $editor) { item in
            CategoryEditScreen(category: item.category)
        }
    }
}

struct CategoryEditorItem: Identifiable {
    let id = UUID()
    let category: CategoryEntity?
}

#Preview("Категории") {
    NavigationStack { CategoriesScreen() }
        .modelContainer(FinanceStore.previewContainer)
}
