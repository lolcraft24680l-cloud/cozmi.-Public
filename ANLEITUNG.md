# COZMI — Schritt fuer Schritt

Alles unten geht am iPhone. Kein Mac, kein PC.

## 1. Dateien bereitlegen
Das ZIP in der Dateien-App antippen. Es entpackt sich in einen Ordner.
Darin liegen sechs Dateien und ein versteckter Ordner `.github`.

## 2. GitHub-Konto
github.com in Safari, "Sign up", kostenlos.

## 3. Repo anlegen
Auf github.com oben rechts das Plus, "New repository".
- Name: cozmi
- Public auswaehlen
- "Add a README file" ankreuzen
- "Create repository"

## 4. Die sechs Dateien hochladen
Im Repo: "Add file" -> "Upload files" -> "choose your files"
-> Dateien-App -> alle sechs auswaehlen:

  COZMIApp.swift, ContentView.swift, Gemini.swift,
  Gesicht.swift, Stimme.swift, make_icon.py, project.yml

Unten "Commit changes".

## 5. Die Workflow-Datei anlegen
Diese eine Datei muss in einem Unterordner liegen, deshalb tippen statt hochladen.

"Add file" -> "Create new file".
Ins Namensfeld genau das hier eintippen:

  .github/workflows/build.yml

(Sobald du den Schraegstrich tippst, legt GitHub den Ordner selbst an.)
Dann den Inhalt von build.yml aus dem entpackten Ordner hineinkopieren.
Unten "Commit changes".

## 6. Warten
Reiter "Actions". Der Lauf startet von selbst, dauert etwa fuenf Minuten.
Gruener Haken = fertig.

## 7. IPA holen
Auf den fertigen Lauf tippen, ganz nach unten scrollen zu "Artifacts",
"COZMI-ipa" antippen. Kommt als ZIP in die Downloads.
In der Dateien-App antippen zum Entpacken. Darin: COZMI.ipa

## 8. Installieren
SideStore oeffnen, Local-Dev-VPN einschalten, Plus antippen,
COZMI.ipa auswaehlen.

## 9. Erster Start
COZMI fragt nach deinem Gemini API-Key.
Holen bei aistudio.google.com/apikey (mit Google-Konto anmelden,
"Create API key", kopieren).

## Bedienung
- Gesicht antippen: zuhoeren. Nach kurzer Stille antwortet er.
- Nochmal antippen: abbrechen.
- Textfeld unten: tippen statt sprechen.
- "Aendere meinen API Key" sagen oder tippen: Schluesseleingabe kommt zurueck.
- Gesicht eine Sekunde halten: dasselbe ohne Sprachbefehl.

## Wenn etwas schiefgeht
Im Actions-Lauf den roten Schritt aufklappen, Text kopieren, mir schicken.
