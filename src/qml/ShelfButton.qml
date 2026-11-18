import QtQuick 2.15

Rectangle {
    id: box

    property string text: ""
    property bool primary: false
    property var pal

    signal clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 36
    width: implicitWidth
    height: implicitHeight
    radius: 6
    color: primary ? (area.pressed ? pal.tealDeep : pal.teal)
                   : (area.containsMouse ? pal.paperDeep : "transparent")
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? pal.ink : (primary ? pal.teal : pal.line)
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: true

    Keys.onReturnPressed: box.clicked()
    Keys.onSpacePressed: box.clicked()

    Text {
        id: label
        anchors.centerIn: parent
        text: box.text
        textFormat: Text.PlainText
        color: box.primary ? box.pal.white : box.pal.ink
        font.pixelSize: 13
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: box.clicked()
    }
}
