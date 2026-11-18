import QtQuick 2.15

// Core already rasterized the page. This is only Image of page-<cid>-N.png
// in this QML document's dir (relative filename, never file://, never data:).
// Do not import Qt PDF. pathFor is this document's resolved PNG path so
// core can QFile-write next to Image, not a QML XHR PUT.
Item {
    id: view
    anchors.fill: parent
    implicitWidth: parent && parent.width > 0 ? parent.width : 640
    implicitHeight: parent && parent.height > 0 ? parent.height : 520

    property string source: ""
    property string failText: ""
    property int page: 0
    property int pageCount: 0
    property string pngUrl: source
    property alias status: pageImage.status
    property int documentStatus: pageImage.status === Image.Ready ? 2
                                 : (pageImage.status === Image.Error ? 4 : 1)
    property int currentPage: page
    property real pageWidth: width
    property real pageHeight: height
    property alias paintedWidth: pageImage.paintedWidth
    property alias paintedHeight: pageImage.paintedHeight

    function pathFor(name) {
        name = String(name || "")
        if (!name || name.indexOf("/") >= 0 || name.indexOf(":") >= 0
                || name.indexOf("..") >= 0 || name.indexOf("file") === 0
                || name.indexOf("data") === 0)
            return ""
        var u = String(Qt.resolvedUrl(name) || "")
        if (u.indexOf("file:") === 0) {
            u = u.replace(/^file:\/\//i, "")
            if (u.indexOf("localhost/") === 0)
                u = u.substring("localhost".length)
            try { u = decodeURIComponent(u) } catch (e) {}
        }
        if (u.charAt(0) === "/" && u.indexOf(".png") > 0 && u.indexOf(":") < 0)
            return u
        return ""
    }

    Rectangle {
        anchors.fill: parent
        color: "#f4f1ea"
        visible: pageCount > 0 && pageImage.status !== Image.Ready
        Text {
            anchors.centerIn: parent
            color: "#5c5346"
            font.pixelSize: 14
            text: view.failText.indexOf("Could not draw") === 0
                  ? view.failText
                  : ("Rendering page " + (view.page + 1) + "…")
        }
    }

    property int loadTries: 0
    property string lastSource: ""
    onSourceChanged: {
        if (view.source !== view.lastSource) {
            view.loadTries = 0
            view.lastSource = view.source
        }
        if (view.source && view.source.indexOf("page-") === 0
                && pageImage.status !== Image.Ready)
            loadRetry.restart()
    }

    Timer {
        id: loadRetry
        interval: 200
        repeat: true
        running: false
        onTriggered: {
            if (pageImage.status === Image.Ready) {
                stop()
                return
            }
            if (!view.source || view.source.indexOf("page-") !== 0) {
                stop()
                return
            }
            view.loadTries++
            var name = view.source
            var dest = view.pathFor(name)
            console.log("parallel-shelf: dest skip core " + dest + " rel=" + name)
            view.source = ""
            Qt.callLater(function () { view.source = name })
        }
    }

    Image {
        id: pageImage
        objectName: "pdfImage"
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: false
        source: view.source
        visible: status === Image.Ready
        onStatusChanged: {
            console.log("parallel-shelf: Image.source=" + view.source
                        + " status=" + status + " dest=" + view.pathFor(view.source))
            if (status === Image.Ready) {
                loadRetry.stop()
                return
            }
            if (!view.source || view.source.indexOf("page-") !== 0) return
            loadRetry.restart()
        }
    }
}
