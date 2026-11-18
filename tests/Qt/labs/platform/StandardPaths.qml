pragma Singleton
import QtQuick 2.15

// Test stand-in for Qt.labs.platform StandardPaths. Basecamp ships the real
// module. qmltestrunner here does not, so this is on the tests import path.
// QML forbids uppercase property names, so AppDataLocation is not declared;
// writableLocation still returns the test AppData path for any loc.
QtObject {
    property string root: "/home/ubuntu/.local/share/parallel-shelf-tests"
    function writableLocation(loc) {
        return root
    }
}
