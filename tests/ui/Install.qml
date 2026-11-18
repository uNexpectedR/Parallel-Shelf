import QtQuick 2.15
import "../../src/qml"

// One person's Basecamp with Parallel Shelf open in it.
Item {
    id: install

    property var network
    property alias basecamp: logos
    property alias shelf: shelf

    width: 960
    height: 680

    // Basecamp puts its bridge in scope under the name `logos`.
    FakeBasecamp {
        id: logos
        network: install.network
        app: shelf
    }

    Main {
        id: shelf
        logosHost: logos
    }
}
