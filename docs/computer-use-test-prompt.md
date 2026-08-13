# Computer Use acceptance test

Copy the following prompt into a fresh ChatGPT Desktop conversation after
rebuilding NixSlop and restarting the app:

```text
Bitte teste jetzt das komplette NixSlop-Computer-Use-Setup auf meinem laufenden
Hyprland-Desktop und gib am Ende einen kompakten, ehrlichen Testbericht aus.

Regeln:
- Verwende ausschließlich reversible Testaktionen und sichere, temporäre
  Fenster/Textfelder. Keine Dateien löschen, keine Einstellungen dauerhaft
  ändern und keine privaten Inhalte öffnen.
- Prüfe jede Funktion mit dem echten Tool-Aufruf und beschreibe nicht nur, dass
  sie laut Konfiguration funktionieren müsste.
- Merke dir vor dem Test Fenstergröße, Fensterposition, Workspace, Fokus und
  Monitor. Stelle am Ende alle Testfenster, Layouts und den ChatGPT-Fokus wieder
  her.
- Wenn ein Test wegen der Testumgebung nicht sinnvoll möglich ist, markiere ihn
  als „nicht geprüft“ und erfinde keinen Erfolg.

1. Grunddiagnose und Koordinatenvertrag

Rufe zuerst `get_app_state` und `doctor` auf. Prüfe im `doctor`-Ergebnis:
- `readiness.blockers` ist leer und AT-SPI, Hyprland, ydotoold und der Socket
  sind bereit;
- `coordinates.applicable` und `coordinates.ready` sind true;
- `coordinates.monitor_count`, `coordinates.origin` und
  `coordinates.capture_scale` sind vorhanden; die Capture-Skalierung ist auf
  meinem Hyprland-Setup 1.0;
- die bevorzugten Backends sind Grim für Screenshots und Hyprland für Fenster.
- `readiness.optional_backends` darf Hinweise auf fehlende GNOME-Schemas oder
  das RemoteDesktop-Portal enthalten. Diese sind unter Hyprland erwartete
  Alternativen und kein Fehler, solange `readiness.blockers` leer ist und die
  bevorzugten nativen Backends bereit sind.

2. Teste alle 18 Funktionen einzeln

`get_app_state`, `doctor`, `list_apps`, `list_windows`, `focused_window`,
`screenshot`, `activate_window`, `click`, `drag`, `move_window`,
`resize_window`, `perform_action`, `set_value`, `setup_accessibility`,
`setup_window_targeting`, `scroll`, `press_key`, `type_text`.

Für `screenshot` prüfe die Bild-Metadaten und die logischen
`coordinate_width`/`coordinate_height`. Für `click` und `drag` verwende ein
eigens geöffnetes Testfenster mit klaren Zielen. Für einen semantischen Klick
verwende einen sichtbaren Button, Checkbox- oder Toggle-Zustand und verifiziere
die Zustandsänderung; ein Tab kann trotz korrektem Pointer-Klick seine Auswahl
wegen eigener App-Logik unverändert lassen. Für `set_value` verwende ein
wirklich editierbares Textfeld. Für `press_key` und `type_text` verwende ein
temporäres Terminal oder Textfeld und verifiziere den tatsächlichen Inhalt,
einschließlich Unterstrich, Bindestrich, Zahlen und Großbuchstaben, zum
Beispiel `CUA_TEXT_OK_-_0123`.

3. Stale-window-Recovery

Wähle ein unkritisches, schwebendes Testfenster und rufe `list_windows` auf.
Führe eine reversible `move_window`- oder `resize_window`-Aktion mit der
aktuellen Fenster-ID aus und merke dir zusätzlich exakt `pid`, `app_id`,
`wm_class` und `title`. Schließe und öffne nur dieses Testfenster neu, sodass
die alte ID veraltet ist. Verwende danach die alte ID **zusammen mit diesen
Identitätsfeldern** für eine zweite reversible Geometrieaktion. Prüfe, dass die
Antwort eine eindeutige Recovery meldet und die neue Fenster-ID/Geometrie
korrekt verwendet. Eine Recovery nur anhand einer nackten alten ID muss aus
Sicherheitsgründen abgelehnt werden. Teste außerdem zwei gleich identifizierte
Fenster und verifiziere, dass kein falsches Fenster verändert wird.

Teste `move_window`/`resize_window` für exakte Pixelwerte mit einem floating
Fenster. Ein tiled Fenster oder ein gedrehtes/zu kleines Monitor-Layout darf
die gewünschte Geometrie durch Hyprland begrenzen; markiere das als
`⚠️ compositor constraint` und vergleiche die zurückgegebene finale Geometrie,
nicht als Plugin-Fehler.

4. Präzision und mehrere Monitore

Führe auf jedem Monitor jeweils vier Mittelpunkt- und vier randnahe Klicks auf
eindeutige Testziele aus. Verifiziere nach jedem Klick den Accessibility-Zustand
und dass kein Nachbarelement aktiviert wurde. Wechsle anschließend mindestens
drei Mal zwischen beiden Monitoren, fokussiere dort je ein Testfenster, mache
jeweils einen Vollbild-Screenshot und prüfe Fokus, Monitor und Koordinaten.
Teste außerdem eine reversible Fensterbewegung und Größenänderung auf beiden
Monitoren. Achte besonders auf negative Ursprünge, unterschiedliche
Auflösungen, Fractional Scaling und den gedrehten Monitor.

Gib am Ende aus:
- eine Liste aller 18 Funktionen mit `✅`, `⚠️` oder `❌`;
- die gemessenen Koordinaten-/Monitorwerte;
- Präzision als Trefferzahl für Mittelpunkt und Randklicks;
- die Zahl erfolgreicher Monitorwechsel;
- jede Abweichung mit der tatsächlichen Tool-Fehlermeldung;
- eine Bestätigung, dass Fensterlayout und Fokus wiederhergestellt wurden.
```
