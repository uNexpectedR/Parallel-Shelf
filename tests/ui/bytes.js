.pragma library

// Byte helpers for the stand-in Logos modules. Bytes are kept the way the
// app keeps them: a string with one character per byte.

function utf8(text) {
    var escaped = encodeURIComponent(text)
    var out = ""
    var i
    for (i = 0; i < escaped.length; i++) {
        if (escaped.charAt(i) === "%") {
            out += String.fromCharCode(parseInt(escaped.substring(i + 1, i + 3), 16))
            i += 2
        } else {
            out += escaped.charAt(i)
        }
    }
    return out
}

function base64(bytes) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var out = ""
    var i
    for (i = 0; i < bytes.length; i += 3) {
        var a = bytes.charCodeAt(i)
        var b = i + 1 < bytes.length ? bytes.charCodeAt(i + 1) : 0
        var c = i + 2 < bytes.length ? bytes.charCodeAt(i + 2) : 0
        out += chars.charAt(a >> 2) + chars.charAt(((a & 3) << 4) | (b >> 4))
        out += i + 1 < bytes.length ? chars.charAt(((b & 15) << 2) | (c >> 6)) : "="
        out += i + 2 < bytes.length ? chars.charAt(c & 63) : "="
    }
    return out
}

// Same bytes, same address, as on real Storage. Not a real hash.
function address(bytes) {
    var a = 5381
    var b = 52711
    var i
    for (i = 0; i < bytes.length; i++) {
        var code = bytes.charCodeAt(i)
        a = ((a * 33) ^ code) >>> 0
        b = ((b * 31) + code) >>> 0
    }
    return "zDvZ" + a.toString(36) + b.toString(36) + bytes.length.toString(36)
}

function readFile(path) {
    try {
        var request = new XMLHttpRequest()
        request.open("GET", "file://" + path, false)
        request.responseType = "arraybuffer"
        request.send()
        if (request.status !== 200) return null
        var view = new Uint8Array(request.response)
        var out = ""
        var i
        for (i = 0; i < view.length; i++) out += String.fromCharCode(view[i])
        return out
    } catch (e) {
        return null
    }
}

function writeFile(path, bytes, done) {
    var view = new Uint8Array(bytes.length)
    var i
    for (i = 0; i < bytes.length; i++) view[i] = bytes.charCodeAt(i)
    var request = new XMLHttpRequest()
    request.onreadystatechange = function () {
        if (request.readyState === 4) done()
    }
    request.open("PUT", "file://" + path)
    request.send(view.buffer)
}
