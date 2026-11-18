import QtQuick 2.15
import TestFileBytes 1.0

// qmltestrunner only. Not packed in the lgx. Share in the view goes through
// logos.callModuleAsync("parallel_shelf_core"), not this plugin.
QtObject {
    property var impl: TestFileBytes
}
