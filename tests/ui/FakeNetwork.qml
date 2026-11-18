import QtQuick 2.15
import "bytes.js" as Bytes

// What the stand-in installs share: the files on Storage, and the messages
// that went over Delivery.
QtObject {
    id: network

    property var files: ({})        // address -> bytes
    property var history: []        // every message sent, oldest first
    property var subscribers: []    // FakeBasecamp objects listening on a topic
    property int historyReads: 0

    // Calls the app made that the real modules would not accept.
    property var mistakes: []

    function mistake(line) {
        mistakes = mistakes.concat([line])
        console.warn("contract: " + line)
    }

    function put(bytes) {
        var cid = Bytes.address(bytes)
        files[cid] = bytes
        return cid
    }

    function send(from, topic, body) {
        var message = { hash: "0x" + (history.length + 1).toString(16), topic: topic, body: body }
        history = history.concat([message])
        var i
        for (i = 0; i < subscribers.length; i++) {
            if (subscribers[i] !== from) subscribers[i].receive(message)
        }
    }
}
