import SwiftUI
import UniformTypeIdentifiers

struct MotionFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { .init(regularFileWithContents: data) }
}

struct ExportStudyView: View {
    @Bindable var studio: StudioModel
    @State private var document: MotionFile?
    @State private var contentType: UTType = .json
    @State private var filename = "trace-motion.json"
    @State private var exporting = false
    @State private var message = "Choose a format, then choose where to save it."

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Export your motion").font(.title2.weight(.medium))
                Spacer()
                Button { studio.exportRequested = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close export").accessibilityIdentifier("closeExport")
            }
            if let take = studio.selectedTake {
                Text("\(take.title) · \(take.duration.formatted(.number.precision(.fractionLength(1)))) seconds")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    exportButton("CSV", detail: "Joint rows for spreadsheets and scripts", type: .commaSeparatedText, id: "exportCSV")
                    exportButton("JSON", detail: "Complete study with tracking confidence", type: .json, id: "exportJSON")
                }
                Text(take.source == .simulatorSample ? "This study contains synthetic simulator data." : "This file contains your recorded hand movement.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Coordinates stay in the original stage, in meters. Turning the replay does not change the export. No video or audio is included.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(message).font(.callout).accessibilityIdentifier("exportStatus")
            } else { Text("Select a study in the studio first.").foregroundStyle(.secondary) }
        }.padding(30).frame(width: 560)
        .fileExporter(isPresented: $exporting, document: document, contentType: contentType, defaultFilename: filename) { result in
            switch result {
            case .success: message = "Export saved. Your study is still on this device."
            case .failure: message = "The export could not be saved. Try choosing another location."
            }
        }
    }
    private func exportButton(_ title: String, detail: String, type: UTType, id: String) -> some View {
        Button {
            guard let take = studio.selectedTake else { return }
            do {
                document = MotionFile(data: type == .json ? try MotionExport.json(take) : MotionExport.csv(take))
                contentType = type; filename = type == .json ? "trace-motion.json" : "trace-motion.csv"; exporting = true
            } catch { message = "The export could not be prepared. Select the study and try again." }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).font(.caption).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        }.buttonStyle(.bordered).accessibilityIdentifier(id)
    }
}
