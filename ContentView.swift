import SwiftUI
import Combine

@MainActor
final class Kopf: ObservableObject {

    @Published var laune: Laune = .ruhe
    @Published var sprecherName = ""
    @Published var untertitel = ""
    @Published var brauchtSchlüssel = false
    @Published var istWechsel = false
    @Published var beschäftigt = false

    let stimme = Stimme()
    private let gemini = Gemini()

    private var schlüssel: String? { Tresor.lies("apikey") }
    private var modell: String {
        UserDefaults.standard.string(forKey: "modell") ?? "gemini-3.8-flash"
    }

    private var weiterleitung: AnyCancellable?

    init() {
        // Stimme ist ein eigenes ObservableObject; SwiftUI bekommt seine
        // Änderungen sonst nicht mit.
        weiterleitung = stimme.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        stimme.beiSatz = { [weak self] text in
            Task { await self?.verarbeite(text) }
        }
        brauchtSchlüssel = (schlüssel == nil)
        if !brauchtSchlüssel { zeige("", "Tipp mich an und sprich.") }
    }

    // MARK: Anzeige

    func zeige(_ wer: String, _ text: String) {
        sprecherName = wer
        untertitel = text
    }

    // MARK: Der Befehl zum Schlüsselwechsel

    private func istSchlüsselBefehl(_ text: String) -> Bool {
        let t = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "ä", with: "a")
        let gegenstand = ["api key", "apikey", "schlussel", "zugang", "key"]
        let tätigkeit  = ["ander", "andre", "wechsel", "wechsle", "tausch",
                          "erneuer", "zurucksetz", "reset", "neuer", "neue"]
        return gegenstand.contains(where: t.contains)
            && tätigkeit.contains(where: t.contains)
    }

    // MARK: Ablauf

    func mikroDrücken() async {
        if stimme.hört { stimme.zuhörenBeenden(); laune = .ruhe; return }
        if beschäftigt { stimme.redenAbbrechen(); beschäftigt = false; laune = .ruhe; return }
        guard await stimme.erlaubnisHolen() else {
            zeige("COZMI", "Ich darf das Mikrofon nicht benutzen. Erlaub es in den Einstellungen — oder tipp mir einfach.")
            return
        }
        untertitel = ""
        laune = .hört
        stimme.zuhören()
    }

    func verarbeite(_ eingabe: String) async {
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !beschäftigt else { return }

        if istSchlüsselBefehl(text) {
            laune = .freut
            zeige("COZMI", "Klar. Gib mir den neuen Schlüssel.")
            stimme.rede("Klar. Gib mir den neuen Schlüssel.")
            istWechsel = true
            brauchtSchlüssel = true
            return
        }

        guard let schlüssel else { brauchtSchlüssel = true; return }

        beschäftigt = true
        laune = .denkt
        zeige("Du", text)

        do {
            let antwort = try await gemini.frage(text, schlüssel: schlüssel, modell: modell)
            zeige("COZMI", antwort)
            laune = .redet
            stimme.rede(antwort)
            while stimme.spricht { try? await Task.sleep(nanoseconds: 120_000_000) }
            laune = .ruhe
        } catch {
            let fehler = (error as? GeminiFehler) ?? .sonstiges(error.localizedDescription)
            laune = .fehler
            zeige("COZMI", fehler.errorDescription ?? "Unbekannter Fehler.")
            stimme.rede(fehler.gesprochen)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if laune == .fehler { laune = .ruhe }
        }
        beschäftigt = false
    }

    // MARK: Einrichtung

    func schlüsselPrüfenUndSpeichern(_ eingabe: String) async -> String? {
        let k = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return "Da steht noch nichts." }
        do {
            let gefunden = try await gemini.modellSuchen(schlüssel: k)
            Tresor.schreib("apikey", k)
            UserDefaults.standard.set(gefunden, forKey: "modell")
            await gemini.verlaufLeeren()
            brauchtSchlüssel = false
            istWechsel = false
            laune = .freut
            zeige("COZMI", "Verbunden. Ich laufe mit \(gefunden). Tipp mich an und sprich einfach los.")
            stimme.rede("Verbunden. Tipp mich an und sprich einfach los.")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if laune == .freut { laune = .ruhe }
            }
            return nil
        } catch let fehler as GeminiFehler {
            if case .schlüsselUngültig = fehler { return "Diesen Schlüssel akzeptiert Google nicht." }
            return fehler.errorDescription
        } catch {
            return error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var kopf = Kopf()
    @State private var getippt = ""
    @FocusState private var tastaturAktiv: Bool

    var body: some View {
        ZStack {
            Color.leere.ignoresSafeArea()

            // Das Licht, das die Augen in den Raum werfen
            RadialGradient(
                colors: [scheinFarbe.opacity(0.16), .clear],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 10, endRadius: 380
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: kopf.laune)

            VStack(spacing: 0) {
                Spacer()

                Gesicht(laune: kopf.laune, takt: kopf.stimme.takt)
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await kopf.mikroDrücken() } }
                    .onLongPressGesture(minimumDuration: 1.0) {
                        kopf.istWechsel = true
                        kopf.brauchtSchlüssel = true
                    }

                Spacer()

                untertitelFeld
                leiste
            }
        }
        .sheet(isPresented: $kopf.brauchtSchlüssel) {
            Einrichtung(kopf: kopf)
                .interactiveDismissDisabled(!kopf.istWechsel)
        }
    }

    private var scheinFarbe: Color {
        switch kopf.laune {
        case .denkt:  return .bernstein
        case .fehler: return .glut
        default:      return .iris
        }
    }

    private var untertitelFeld: some View {
        ScrollView {
            VStack(spacing: 5) {
                if !kopf.sprecherName.isEmpty {
                    Text(kopf.sprecherName)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                Text(kopf.stimme.hört && !kopf.stimme.mitschrift.isEmpty
                     ? kopf.stimme.mitschrift
                     : kopf.untertitel)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 30)
        }
        .frame(maxHeight: 190)
        .animation(.easeInOut(duration: 0.25), value: kopf.untertitel)
    }

    private var leiste: some View {
        HStack(spacing: 10) {
            TextField("Tippen oder Mikro antippen", text: $getippt)
                .font(.system(size: 16, design: .rounded))
                .focused($tastaturAktiv)
                .submitLabel(.send)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .padding(.horizontal, 16).padding(.vertical, 13)
                .background(Color.white.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.07)))
                .onSubmit {
                    let t = getippt; getippt = ""; tastaturAktiv = false
                    Task { await kopf.verarbeite(t) }
                }

            Button {
                tastaturAktiv = false
                Task { await kopf.mikroDrücken() }
            } label: {
                Image(systemName: kopf.stimme.hört ? "waveform" : "mic.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(kopf.stimme.hört ? Color.iris : Color.white.opacity(0.42))
                    .frame(width: 46, height: 46)
                    .background(
                        Circle().fill(kopf.stimme.hört
                                      ? Color.iris.opacity(0.14)
                                      : Color.white.opacity(0.04))
                    )
                    .overlay(Circle().stroke(kopf.stimme.hört
                                             ? Color.irisTief
                                             : Color.white.opacity(0.07)))
            }
            .scaleEffect(kopf.stimme.hört ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: kopf.stimme.hört)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

struct Einrichtung: View {
    @ObservedObject var kopf: Kopf
    @State private var eingabe = ""
    @State private var hinweis = ""
    @State private var fehlerhaft = false
    @State private var prüft = false
    @FocusState private var fokus: Bool

    var body: some View {
        ZStack {
            Color.leere.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text(kopf.istWechsel ? "Neuer Schlüssel." : "Hallo. Ich brauche deinen Schlüssel.")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text("Füge deinen Gemini API-Key ein. Er bleibt im Schlüsselbund dieses iPhones und geht nur an Google. Holen kannst du ihn dir bei aistudio.google.com.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))

                TextField("AIza…", text: $eingabe)
                    .font(.system(size: 16, design: .monospaced))
                    .focused($fokus)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(15)
                    .background(Color.white.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.1)))
                    .onSubmit { prüfen() }

                HStack(spacing: 10) {
                    Button(action: prüfen) {
                        Text(prüft ? "Prüfe…" : "Verbinden")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.leere)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.iris,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(prüft)
                    .opacity(prüft ? 0.5 : 1)

                    if kopf.istWechsel {
                        Button("Zurück") {
                            kopf.istWechsel = false
                            kopf.brauchtSchlüssel = false
                        }
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 18).padding(.vertical, 15)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.1)))
                    }
                }

                Text(hinweis)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(fehlerhaft ? Color.glut : Color.white.opacity(0.4))
                    .frame(minHeight: 18, alignment: .leading)
            }
            .padding(.horizontal, 28)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { fokus = true } }
    }

    private func prüfen() {
        prüft = true
        hinweis = "Prüfe den Schlüssel…"
        fehlerhaft = false
        Task {
            if let problem = await kopf.schlüsselPrüfenUndSpeichern(eingabe) {
                hinweis = problem
                fehlerhaft = true
            }
            prüft = false
        }
    }
}
