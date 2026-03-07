import SwiftUI

struct ActivityLogView: View {
  @ObservedObject private var activityLog = ActivityLog.shared
  @State private var searchText = ""
  @State private var selectedCategories: Set<LogCategory> = Set(LogCategory.allCases)

  private var filteredEntries: [LogEntry] {
    activityLog.entries.filter { entry in
      let categoryMatch = selectedCategories.contains(entry.category)
      let searchMatch = searchText.isEmpty ||
        entry.message.localizedCaseInsensitiveContains(searchText) ||
        entry.category.displayName.localizedCaseInsensitiveContains(searchText)
      return categoryMatch && searchMatch
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Toolbar
      HStack {
        TextField("Search...", text: $searchText)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 200)

        Spacer()

        Menu("Filter") {
          Button(selectedCategories.count == LogCategory.allCases.count ? "Deselect All" : "Select All") {
            if selectedCategories.count == LogCategory.allCases.count {
              selectedCategories.removeAll()
            } else {
              selectedCategories = Set(LogCategory.allCases)
            }
          }
          Divider()
          ForEach(LogCategory.allCases, id: \.self) { category in
            Button {
              if selectedCategories.contains(category) {
                selectedCategories.remove(category)
              } else {
                selectedCategories.insert(category)
              }
            } label: {
              HStack {
                Text("\(category.icon) \(category.displayName)")
                Spacer()
                if selectedCategories.contains(category) {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 70)

        Button(action: copyToClipboard) {
          Image(systemName: "doc.on.doc")
        }
        .help("Copy to Clipboard")

        Button(action: clearLog) {
          Image(systemName: "trash")
        }
        .help("Clear Log")
      }
      .padding(8)

      Divider()

      // Log entries
      if filteredEntries.isEmpty {
        VStack {
          Spacer()
          Text("No log entries")
            .foregroundColor(.secondary)
          Spacer()
        }
      } else {
        List(filteredEntries) { entry in
          LogEntryRow(entry: entry)
        }
        .listStyle(.plain)
      }

      Divider()

      // Status bar
      HStack {
        Text("\(filteredEntries.count) of \(activityLog.entries.count) entries")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
    }
    .frame(width: 500, height: 400)
  }

  private func copyToClipboard() {
    let text = activityLog.exportAsText()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func clearLog() {
    activityLog.clear()
  }
}

struct LogEntryRow: View {
  let entry: LogEntry

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  private var formattedTime: String {
    Self.timeFormatter.string(from: entry.timestamp)
  }

  private var categoryColor: Color {
    switch entry.category {
    case .system: return .gray
    case .armed: return .green
    case .disarmed: return .red
    case .trigger: return .orange
    case .theft: return .red
    case .telegram: return .blue
    case .power: return .yellow
    case .location: return .cyan
    case .bluetooth: return .teal
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(formattedTime)
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(width: 60, alignment: .leading)

      Text(entry.category.icon)
        .frame(width: 20)

      Text(entry.category.displayName)
        .font(.caption)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(categoryColor.opacity(0.2))
        .cornerRadius(4)
        .frame(width: 70, alignment: .leading)

      Text(entry.message)
        .font(.system(.body, design: .default))
        .lineLimit(2)
    }
    .padding(.vertical, 2)
  }
}
