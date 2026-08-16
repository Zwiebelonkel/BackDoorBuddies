# Blender-Räume im prozeduralen Generator

## Zielstruktur

Ein Blender-Export ist nur die visuelle Ebene. Die prozedurale und spielerische
Konfiguration bleibt in einer Godot-`.tscn`, damit ein erneuter Blender-Export
keine Sockets, Spawnpunkte oder Kollisionen überschreibt.

```text
ProceduralRoom
├── Visuals
│   └── ImportedRoomVisual
├── GameplayCollision
├── RoomBounds
│   └── CollisionShape3D
├── DoorSockets
│   └── Socket...
└── ItemSpawnPoints
    └── Floor...
```

## Blender vorbereiten

1. In Metern modellieren: eine Blender-Einheit entspricht einem Meter.
2. Den Raumboden auf `Y = 0` und den Raumursprung sinnvoll in die Grundfläche
   setzen.
3. Rotation und Skalierung vor dem Export anwenden.
4. Das Modell als `.glb` nach `res://models/rooms/` exportieren. Materialien und
   Texturen möglichst mit eindeutigen Namen versehen.

## Godot-Raumszene anlegen

1. `blender_room_template.tscn` duplizieren und passend umbenennen.
2. Die importierte `.glb` unter `Visuals` instanziieren. Für dauerhafte
   Material- oder Node-Anpassungen kann zuerst eine von der `.glb` geerbte
   Visual-Szene erstellt und diese instanziiert werden.
3. `GameplayCollision` an den Raum anpassen. Begehbare Flächen müssen auf
   Physics Layer 1 liegen, damit Spieler und Item-Spawn-Rays sie erkennen.
4. Die `RoomBounds`-Box über den gesamten Raum legen, aber an Anschlussflächen
   etwa drei Zentimeter innerhalb der Wand-/Socket-Ebene enden lassen.
5. Für jede nutzbare Tür einen `RoomSocket` unter `DoorSockets` anlegen:
   - Position: Mitte der Türöffnung auf Bodenhöhe.
   - Ausrichtung: Die lokale `+Z`-Achse zeigt aus dem Raum heraus.
   - `room_door` verbindet Zimmer mit seitlichen Flur-Türen.
   - `corridor` verbindet Flurenden miteinander.
6. `ItemSpawnPoints` auf freie Stellen setzen. Sie raycasten nach unten auf
   Layer 1 und setzen Items auf die gefundene Oberfläche.
7. In `scenes/main.tscn` die fertige Godot-Raumszene zum Array `room_scenes` des
   `ProceduralLevelGenerator` hinzufügen. Niemals die rohe `.glb` eintragen.

## Zusätzliche Start-Raum-Nodes

Soll ein Blender-Raum der Start-Raum sein, benötigt er außerdem:

- einen `PlayerArrival`-Marker in der Gruppe `procedural_spawn_point`,
- die Ausgangstür zurück zur Halle,
- mindestens einen passenden Anschluss-Socket.

## Kontrollliste

- Keine sichtbare Wand ragt über `RoomBounds` in den Nachbarraum.
- Socket-Positionen liegen exakt auf derselben Anschluss-Ebene.
- Die Türöffnung passt zum verwendeten `cap_scene`; andernfalls eine eigene
  Abschlusswand verwenden.
- Kollisionsflächen sind nicht doppelt vorhanden.
- Die fertige `.tscn` hat `ProceduralRoom` am Root und lässt sich einzeln öffnen.
