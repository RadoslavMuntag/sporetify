//@ pragma AppId sporetify-gallery

import QtQuick
import Quickshell

import "app"
import "common"
import "compact"

// A sheet of the Field Guide's parts in every state, for judging a visual
// change by eye (design milestone V1). Made-up tracks; no daemon needed.
//
//   qs -p <repo>/Gallery.qml
//   SPORETIFY_GALLERY_SHOT=/tmp/sheet.png QT_QPA_PLATFORM=offscreen qs -p <repo>/Gallery.qml
//
// With SPORETIFY_GALLERY_SHOT set it saves a picture of itself and quits.
// For another theme, point HOME at a folder holding only
// .local/state/omarchy/current/theme/colors.toml (see CLAUDE.md).
ShellRoot {
  FloatingWindow {
    id: window
    title: "Sporetify gallery"
    color: Theme.background
    implicitWidth: page.width
    implicitHeight: page.height

    readonly property var ids: ["spotify:track:silver-lining", "spotify:track:marigold", "spotify:track:lighthouse", "spotify:track:tide-pool"]

    // Stands in for common/Player.qml.
    component Fake: QtObject {
      property var track: null
      property bool playing: true
      property string phase: "ready"
      property string scope: "player"
      property string lastError: ""
      property var player: ({ position: { position_ms: 55000, at_ms: Date.now(), rate: 0 } })
      // A still frame of music, so the spectrum shows.
      property var bands: [0.82, 0.95, 0.74, 0.6, 0.66, 0.52, 0.58, 0.47, 0.41, 0.46, 0.35, 0.3, 0.33, 0.22, 0.15, 0.08]
      property real beat: 0.4
    }
    component Caption: Text {
      textFormat: Text.PlainText
      color: Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.caption
    }
    component Frame: Rectangle {
      color: "transparent"
      border.width: Theme.stroke.hair
      border.color: Theme.line
    }

    Fake {
      id: playing
      track: ({ id: window.ids[0], title: "Silver Lining", artists: ["North Atlas"], album: "Second Shoreline", duration_ms: 277000 })
    }
    Fake {
      id: paused
      playing: false
      track: ({ id: window.ids[1], title: "Marigold", artists: ["Odd Meridian", "Juno Vale"], album: "A Map of Small Hours", duration_ms: 225000 })
      player: ({ position: { position_ms: 190000, at_ms: Date.now(), rate: 0 } })
    }
    Fake { id: idle }
    Fake { id: fault; phase: "unavailable"; scope: "fault" }

    Rectangle {
    id: page
    width: sheet.implicitWidth + Theme.spacing.huge * 2
    height: sheet.implicitHeight + Theme.spacing.huge * 2
    color: Theme.background

    Column {
      id: sheet
      x: Theme.spacing.huge
      y: Theme.spacing.huge
      spacing: Theme.spacing.huge

      Caption { text: "LENS · sizes 72 / 140 / 240, four tracks, the last with visuals off" }
      Row {
        spacing: Theme.spacing.huge
        Repeater {
          model: [72, 140, 240]
          Lens {
            required property int modelData
            width: Theme.space(modelData)
            height: width
            seed: window.ids[2]
            progress: 0.35
            alive: true
            palette: Theme.creatureColors
            ground: Theme.sunken
            ink: Theme.foreground
            accent: Theme.accent
            eye: Theme.foreground
            pupil: Theme.sunken
            stroke: Theme.stroke.hair
          }
        }
        Repeater {
          model: 2
          Lens {
            required property int index
            width: Theme.space(140)
            height: width
            seed: window.ids[3 - index]
            progress: 0.8
            creature: index === 0
            palette: Theme.creatureColors
            ground: Theme.sunken
            ink: Theme.foreground
            accent: Theme.accent
            eye: Theme.foreground
            pupil: Theme.sunken
            stroke: Theme.stroke.hair
          }
        }
      }

      Caption { text: "COMPACT PLAYER · square, wide, tall · playing, paused (reduced), nothing loaded, daemon missing" }
      Row {
        spacing: Theme.spacing.huge
        Frame {
          width: Theme.space(340); height: Theme.space(480)
          CompactView { anchors.fill: parent; anchors.margins: 1; player: playing }
        }
        Column {
          spacing: Theme.spacing.huge
          Frame {
            width: Theme.space(770); height: Theme.space(250)
            CompactView { anchors.fill: parent; anchors.margins: 1; player: paused; visuals: "reduced" }
          }
          Row {
            spacing: Theme.spacing.huge
            Frame {
              width: Theme.space(330); height: Theme.space(190)
              CompactView { anchors.fill: parent; anchors.margins: 1; player: idle }
            }
            Frame {
              width: Theme.space(420); height: Theme.space(190)
              CompactView { anchors.fill: parent; anchors.margins: 1; player: fault }
            }
          }
        }
        Frame {
          width: Theme.space(280); height: Theme.space(480)
          CompactView { anchors.fill: parent; anchors.margins: 1; player: playing; visuals: "off" }
        }
      }
    }

    }

    Timer {
      running: Quickshell.env("SPORETIFY_GALLERY_SHOT") !== null && Quickshell.env("SPORETIFY_GALLERY_SHOT") !== ""
      interval: 1500
      onTriggered: page.grabToImage(function(result) {
        result.saveToFile(Quickshell.env("SPORETIFY_GALLERY_SHOT"))
        Qt.quit()
      })
    }
  }
}
