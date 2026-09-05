import SwiftUI

enum Laune {
    case ruhe, hört, denkt, redet, freut, fehler
}

extension Color {
    static let leere      = Color(red: 0.024, green: 0.027, blue: 0.039)
    static let irisHell   = Color(red: 0.71,  green: 0.96,  blue: 1.0)
    static let iris       = Color(red: 0.36,  green: 0.91,  blue: 1.0)
    static let irisTief   = Color(red: 0.11,  green: 0.62,  blue: 0.77)
    static let bernstein  = Color(red: 1.0,   green: 0.82,  blue: 0.29)
    static let bernsteinT = Color(red: 0.79,  green: 0.56,  blue: 0.06)
    static let glut       = Color(red: 1.0,   green: 0.35,  blue: 0.35)
    static let glutTief   = Color(red: 0.63,  green: 0.13,  blue: 0.13)
}

/// Ein einzelnes Auge: leuchtender Block, darüber ein Lid, das eine Kurve hineinschneidet.
struct Auge: View {
    let breite: CGFloat
    let höhe: CGFloat
    let farben: [Color]
    let lidHoch: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: farben, startPoint: .top, endPoint: .bottom)

            // CRT-Textur eines Spielzeugdisplays
            LinearGradient(
                stops: [.init(color: .black.opacity(0.16), location: 0),
                        .init(color: .clear,               location: 0.25)],
                startPoint: .top, endPoint: .bottom
            )
            .mask(
                VStack(spacing: 3) {
                    ForEach(0..<40, id: \.self) { _ in
                        Rectangle().frame(height: 1)
                    }
                }
            )
            .blendMode(.multiply)

            // Das Lid liegt normalerweise unterhalb des Auges und fährt zum Lächeln hoch.
            Ellipse()
                .fill(Color.leere)
                .frame(width: breite * 1.5, height: höhe * 1.15)
                .offset(y: lidHoch ? höhe * 0.62 : höhe * 1.25)
        }
        .frame(width: breite, height: höhe)
        .clipShape(RoundedRectangle(cornerRadius: breite * 0.28, style: .continuous))
        .shadow(color: farben[1].opacity(0.55), radius: 30)
        .shadow(color: farben[1].opacity(0.25), radius: 80)
    }
}

struct Gesicht: View {
    let laune: Laune
    /// Zählt bei jedem gesprochenen Wort hoch.
    let takt: Int

    @State private var lidschlag: CGFloat = 1
    @State private var wippen: CGFloat = 0
    @State private var schwenk: CGFloat = 0
    @State private var drift: CGSize = .zero

    private var breite: CGFloat { 112 }

    private var höhe: CGFloat {
        switch laune {
        case .ruhe:   return 150
        case .hört:   return 170
        case .denkt:  return 52
        case .redet:  return 136
        case .freut:  return 150
        case .fehler: return 64
        }
    }

    private var farben: [Color] {
        switch laune {
        case .denkt:  return [.white.opacity(0.9), .bernstein, .bernsteinT]
        case .fehler: return [.white.opacity(0.85), .glut, .glutTief]
        default:      return [.irisHell, .iris, .irisTief]
        }
    }

    var body: some View {
        HStack(spacing: 50) {
            Auge(breite: breite, höhe: höhe, farben: farben, lidHoch: laune == .freut)
                .rotationEffect(.degrees(laune == .fehler ? 9 : 0))
            Auge(breite: breite, höhe: höhe, farben: farben, lidHoch: laune == .freut)
                .rotationEffect(.degrees(laune == .fehler ? -9 : 0))
        }
        .scaleEffect(x: 1, y: lidschlag, anchor: .center)
        .scaleEffect(laune == .hört ? 1.06 : 1)
        .offset(x: drift.width + schwenk,
                y: drift.height + wippen + (laune == .freut ? -10 : 0))
        .animation(.spring(response: 0.38, dampingFraction: 0.62), value: laune)
        .animation(.easeInOut(duration: 0.09), value: lidschlag)
        .onReceive(uhr) { _ in tick() }
        .onChange(of: takt) { _, _ in
            guard laune == .redet else { return }
            withAnimation(.easeOut(duration: 0.09)) { wippen = -9 }
            withAnimation(.easeIn(duration: 0.13).delay(0.09)) { wippen = 0 }
        }
        .onChange(of: laune) { _, neu in
            if neu == .denkt { schwenkStarten() } else {
                withAnimation(.easeOut(duration: 0.3)) { schwenk = 0 }
            }
        }
    }

    private let uhr = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// Ein halbsekündlicher Puls treibt Blinzeln und Blickdrift — beides
    /// wird unterdrückt, wenn das Gesicht gerade denkt oder streikt.
    private func tick() {
        let lebendig = (laune != .denkt && laune != .fehler)

        if lebendig, lidschlag == 1, Double.random(in: 0...1) < 0.13 {
            lidschlag = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { lidschlag = 1 }
        }

        if Double.random(in: 0...1) < 0.12 {
            withAnimation(.easeInOut(duration: 2.4)) {
                drift = CGSize(width: .random(in: -8...8), height: .random(in: -5...5))
            }
        }
    }

    private func schwenkStarten() {
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
            schwenk = 14
        }
    }
}
