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

2. Teste alle 18 Funktionen einzeln

`get_app_state`, `doctor`, `list_apps`, `list_windows`, `focused_window`,
`screenshot`, `activate_window`, `click`, `drag`, `move_window`,
`resize_window`, `perform_action`, `set_value`, `setup_accessibility`,
`setup_window_targeting`, `scroll`, `press_key`, `type_text`.

Für `screenshot` prüfe die Bild-Metadaten und die logischen
`coordinate_width`/`coordinate_height`. Für `click` und `drag` verwende ein
eigens geöffnetes Testfenster mit klaren Zielen. Für `set_value` verwende ein
wirklich editierbares Textfeld. Für `press_key` und `type_text` verwende ein
temporäres Terminal oder Textfeld und verifiziere den tatsächlichen Inhalt,
einschließlich Unterstrich, Bindestrich, Zahlen und Großbuchstaben, zum
Beispiel `CUA_TEXT_OK_-_0123`.

3. Stale-window-Recovery

Wähle ein unkritisches Testfenster und rufe `list_windows` auf. Führe eine
reversible `move_window`- oder `resize_window`-Aktion mit der aktuellen
Fenster-ID aus. Schließe und öffne nur dieses Testfenster neu, sodass die alte
ID veraltet ist. Verwende danach die alte ID für eine zweite reversible
Geometrieaktion und prüfe, dass das Ergebnis eine eindeutige Recovery meldet
und die neue Fenster-ID/Geometrie korrekt verwendet. Falls die alte ID nicht
mehr als Ziel übergeben werden kann, markiere nur diesen Teil als nicht
geprüft; teste trotzdem, dass eine frische `list_windows`-Abfrage funktioniert.

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
