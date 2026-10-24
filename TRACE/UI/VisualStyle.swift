import SwiftUI

enum TraceStyle {
    static let chalk = Color(red: 0.13, green: 0.14, blue: 0.15)
    static let coral = Color(red: 0.88, green: 0.27, blue: 0.22)
    static let blue = Color(red: 0.43, green: 0.46, blue: 0.49)
    static let graphite = Color(red: 0.13, green: 0.14, blue: 0.15)
    static let paper = Color(red: 0.99, green: 0.99, blue: 0.985)

}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(TraceStyle.blue) }
}
struct ChamberEmblem: View {
    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                Ellipse().stroke(TraceStyle.chalk.opacity(0.08 + Double(index) * 0.035), lineWidth: 1)
                    .frame(width: CGFloat(100 + index * 45), height: CGFloat(40 + index * 24))
            }
            Path { path in
                path.move(to: CGPoint(x: 35, y: 100))
                path.addCurve(to: CGPoint(x: 218, y: 70), control1: CGPoint(x: 95, y: -15), control2: CGPoint(x: 160, y: 190))
            }.stroke(TraceStyle.coral, style: .init(lineWidth: 3, lineCap: .round))
            Circle().fill(TraceStyle.chalk).frame(width: 7, height: 7).offset(x: 88, y: -10)
        }.frame(width: 260, height: 120).accessibilityHidden(true)
    }
}
