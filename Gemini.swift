import Foundation

enum GeminiFehler: LocalizedError {
    case schlüsselUngültig
    case kontingent
    case netz
    case leer
    case sonstiges(String)

    var errorDescription: String? {
        switch self {
        case .schlüsselUngültig: return "Der Schlüssel wird nicht akzeptiert."
        case .kontingent:        return "Dein Kontingent bei Google ist gerade aufgebraucht."
        case .netz:              return "Keine Verbindung."
        case .leer:              return "Gemini hat nichts zurückgegeben."
        case .sonstiges(let m):  return m
        }
    }

    /// Was COZMI dazu laut sagt.
    var gesprochen: String {
        switch self {
        case .schlüsselUngültig: return "Mein Schlüssel wird nicht mehr akzeptiert. Sag: ändere meinen API Key."
        case .kontingent:        return "Dein Kontingent ist gerade aufgebraucht. Probier es gleich noch mal."
        case .netz:              return "Ich komme nicht ins Netz."
        case .leer:              return "Da kam nichts zurück."
        case .sonstiges:         return "Da ging etwas schief."
        }
    }
}

actor Gemini {
    private let basis = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    private let wunschmodelle = ["gemini-3.8-flash", "gemini-3.6-flash",
                                 "gemini-2.5-flash", "gemini-2.0-flash"]

    private var verlauf: [[String: Any]] = []

    private let systemText = """
    Du bist COZMI, ein kleiner Tischroboter mit großem Herz und leicht frecher Persönlichkeit.
    Du sprichst Deutsch und antwortest so, dass deine Worte laut vorgelesen werden können:
    - kurz: normalerweise ein bis drei Sätze, nur bei echten Erklärfragen mehr
    - gesprochen, nicht geschrieben: keine Aufzählungszeichen, keine Überschriften, keine Emojis, keine Sternchen
    - Zahlen und Abkürzungen ausschreiben, wenn sie sonst seltsam klingen
    - warm, direkt, gelegentlich trocken witzig, niemals unterwürfig
    Wenn du etwas nicht weißt, sag das in einem Satz.
    """

    func verlaufLeeren() { verlauf.removeAll() }

    // MARK: Modellsuche

    /// Prüft den Schlüssel und liefert das beste verfügbare Modell zurück.
    func modellSuchen(schlüssel: String) async throws -> String {
        var anfrage = URLRequest(url: basis.appendingPathComponent("models"))
        anfrage.setValue(schlüssel, forHTTPHeaderField: "x-goog-api-key")
        anfrage.timeoutInterval = 20

        let (daten, antwort) = try await senden(anfrage)
        try prüfe(antwort, daten)

        let objekt = try JSONSerialization.jsonObject(with: daten) as? [String: Any]
        let liste = objekt?["models"] as? [[String: Any]] ?? []

        let nutzbar: [String] = liste.compactMap { modell in
            let methoden = modell["supportedGenerationMethods"] as? [String] ?? []
            guard methoden.contains("generateContent"),
                  let name = modell["name"] as? String else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }

        if let treffer = wunschmodelle.first(where: { nutzbar.contains($0) }) { return treffer }
        if let flash = nutzbar.first(where: {
            $0.contains("flash") && !$0.contains("image") && !$0.contains("tts")
                && !$0.contains("live") && !$0.contains("embed")
        }) { return flash }
        if let erstes = nutzbar.first { return erstes }
        throw GeminiFehler.sonstiges("Dieser Schlüssel gibt kein nutzbares Modell frei.")
    }

    // MARK: Unterhaltung

    func frage(_ text: String, schlüssel: String, modell: String) async throws -> String {
        verlauf.append(["role": "user", "parts": [["text": text]]])
        if verlauf.count > 24 { verlauf.removeFirst(verlauf.count - 24) }

        let körper: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemText]]],
            "contents": verlauf,
            "generationConfig": ["temperature": 0.85, "maxOutputTokens": 800]
        ]

        var anfrage = URLRequest(url: basis
            .appendingPathComponent("models")
            .appendingPathComponent("\(modell):generateContent"))
        anfrage.httpMethod = "POST"
        anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
        anfrage.setValue(schlüssel, forHTTPHeaderField: "x-goog-api-key")
        anfrage.httpBody = try JSONSerialization.data(withJSONObject: körper)
        anfrage.timeoutInterval = 60

        do {
            let (daten, antwort) = try await senden(anfrage)
            try prüfe(antwort, daten)

            let objekt = try JSONSerialization.jsonObject(with: daten) as? [String: Any]
            let kandidaten = objekt?["candidates"] as? [[String: Any]] ?? []
            let teile = (kandidaten.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            let ergebnis = teile.compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !ergebnis.isEmpty else { verlauf.removeLast(); throw GeminiFehler.leer }
            verlauf.append(["role": "model", "parts": [["text": ergebnis]]])
            return ergebnis
        } catch {
            if verlauf.last?["role"] as? String == "user" { verlauf.removeLast() }
            throw error
        }
    }

    // MARK: Hilfsmittel

    private func senden(_ anfrage: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await URLSession.shared.data(for: anfrage) }
        catch { throw GeminiFehler.netz }
    }

    private func prüfe(_ antwort: URLResponse, _ daten: Data) throws {
        guard let http = antwort as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any]
        let meldung = ((objekt?["error"] as? [String: Any])?["message"] as? String)
            ?? "HTTP \(http.statusCode)"

        switch http.statusCode {
        case 400 where meldung.localizedCaseInsensitiveContains("api key"),
             401, 403:
            throw GeminiFehler.schlüsselUngültig
        case 429:
            throw GeminiFehler.kontingent
        default:
            throw GeminiFehler.sonstiges(meldung)
        }
    }
}
