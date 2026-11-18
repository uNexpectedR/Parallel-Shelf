import QtQuick
import QtMultimedia

// Kept in its own file and loaded on demand. If this Basecamp build has no
// audio playback, only this file fails and the shelf still opens.
Item {
    id: box

    readonly property bool playing: media.playbackState === MediaPlayer.PlayingState
    readonly property int position: media.position
    readonly property int duration: media.duration

    signal failed(string why)

    function load(url) {
        media.source = url
        media.play()
    }

    function toggle() {
        if (box.playing) media.pause()
        else media.play()
    }

    function seek(ms) {
        media.position = ms
    }

    function stop() {
        media.stop()
        media.source = ""
    }

    MediaPlayer {
        id: media
        audioOutput: AudioOutput {}
        onErrorOccurred: function (error, errorString) {
            box.failed(errorString)
        }
    }
}
