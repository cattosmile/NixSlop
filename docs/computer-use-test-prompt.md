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
- Verwende für AT-SPI-Semantiktests nicht Kitty als einziges Testfenster. Kitty
  und manche Terminal-Apps liefern trotz aktiver AT-SPI-Verbindung keinen
  brauchbaren Accessibility-Baum. Bevorzuge ein zugängliches GTK-/Qt-Fenster,
  zum Beispiel ein leeres Mousepad-Dokument, falls Mousepad installiert ist.

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
wirklich editierbares Textfeld und akzeptiere `ok: true` nur, wenn ein frischer
AT-SPI-Readback exakt den gesetzten Wert enthält. Falls der Readback leer oder
veraltet bleibt, melde die tatsächliche Tool-Fehlermeldung und teste danach mit
einem frischen `element_index` oder eindeutigen Selector weiter. Prüfe außerdem
`perform_action` mit `action: "click"` an einem Element, dessen AT-SPI-
Primäraktion namenlos ist; der Aufruf soll auf die Primäraktion zurückfallen.
Rufe für diese beiden Tests zuerst `get_app_state` gezielt für das zugängliche
GTK-/Qt-Fenster auf und verifiziere, dass der Baum tatsächlich Nodes enthält.
Wenn kein zugängliches Testfenster verfügbar ist, kennzeichne die beiden
Funktionen als „nicht geprüft“ und nenne den konkreten Grund aus der Tool-
Antwort; ein leerer Kitty-Baum ist kein Plugin-Erfolg und kein Plugin-Fehler.
Für `press_key` und `type_text` verwende ein temporäres Terminal oder Textfeld
und verifiziere den tatsächlichen Inhalt, einschließlich Unterstrich,
Bindestrich, Zahlen und Großbuchstaben, zum Beispiel `CUA_TEXT_OK_-_0123`.

Auf Hyprland sind Screenshot-/Pointer-Koordinaten normalerweise 0-basierte
Capture-Pixel. Teste auf dem Monitor mit negativem Ursprung zusätzlich einen
gültigen negativen Hyprland-Globalpunkt (zum Beispiel direkt aus einem AT-SPI-
oder Fenster-Bounds-Ergebnis). Der Plugin-Helper darf diesen Punkt genau einmal
in den Capture-Raum normalisieren und muss die Umrechnung im Ergebnis erwähnen;
ein Punkt, der bereits im Screenshot-Raum liegt, darf nicht doppelt umgerechnet
werden.

3. Stale-window-Recovery

Wähle ein unkritisches, schwebendes Testfenster und rufe `list_windows` auf.
Führe eine reversible `move_window`- oder `resize_window`-Aktion mit der
aktuellen Fenster-ID aus und merke dir zusätzlich exakt `pid`, `app_id`,
`wm_class` und `title`. Schließe und öffne nur dieses Testfenster neu, sodass
die alte ID veraltet ist. Teile den Test danach ausdrücklich in drei Fälle:

1. Verwende die alte ID **zusammen mit den Identitätsfeldern** für eine zweite
   reversible Geometrieaktion. Nur eine eindeutige Meldung wie
   `Recovered stale window handle ...` zählt als erfolgreiche Recovery; prüfe
   die neue Fenster-ID und die finale Geometrie.
2. Wiederhole die Aktion nur mit der nackten alten ID. Sie muss mit einer
   Meldung wie `rejected without performing an action` sicher abgelehnt werden.
3. Teste zwei gleich identifizierte Fenster. Kein Fenster darf verändert
   werden; die Antwort muss eine sichere Ablehnung wegen fehlender eindeutiger
   Recovery melden.

Eine reine Ablehnung darf nicht als erfolgreiche Recovery gezählt werden, ist
aber für den nackten-ID- und den Mehrdeutigkeitsfall das erwartete Ergebnis.

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

Für `scroll` verwende ein temporäres, tatsächlich scrollbares Testziel. Am
zuverlässigsten ist ein leeres Mousepad-Dokument, in das du viele nummerierte
Zeilen über `type_text` einfügst; alternativ geht eine lokale scrollbare
Testansicht. Fotografiere den Ausgangszustand, scrolle und verifiziere eine
sichtbare Änderung. Ein statisches/nicht scrollbares Chat- oder Kitty-Fenster
zählt nur als „Aktion gesendet“, nicht als vollständig verifizierter
Scroll-Erfolg.

Gib am Ende aus:
- eine Liste aller 18 Funktionen mit `✅`, `⚠️` oder `❌`;
- die gemessenen Koordinaten-/Monitorwerte;
- Präzision als Trefferzahl für Mittelpunkt und Randklicks;
- die Zahl erfolgreicher Monitorwechsel;
- jede Abweichung mit der tatsächlichen Tool-Fehlermeldung;
- eine Bestätigung, dass Fensterlayout und Fokus wiederhergestellt wurden.
```
