import QtQuick 2.15

Rectangle {
    id: box

    property alias text: input.text
    property alias maximumLength: input.maximumLength
    property alias cursorPosition: input.cursorPosition
    property bool wrap: false
    property string placeholder: ""
    property var pal

    height: wrap ? Math.max(38, input.contentHeight + 18) : 38
    radius: 6
    color: pal.white
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? pal.teal : pal.line

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: wrap ? TextInput.AlignTop : TextInput.AlignVCenter
        anchors.topMargin: wrap ? 8 : 0
        color: box.pal.ink
        selectionColor: box.pal.teal
        font.pixelSize: 14
        clip: true
        wrapMode: wrap ? TextInput.WrapAnywhere : TextInput.NoWrap
        selectByMouse: true
        activeFocusOnTab: true
        onAccepted: box.accepted()
    }

    signal accepted()

    Text {
        anchors.fill: input
        verticalAlignment: box.wrap ? Text.AlignTop : Text.AlignVCenter
        text: box.placeholder
        textFormat: Text.PlainText
        color: box.pal.mute
        font.pixelSize: 14
        elide: Text.ElideRight
        visible: input.text.length === 0
    }
}
