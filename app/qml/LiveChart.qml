// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
// LiveChart.qml — canvas-based scrolling multi-series chart
// Adapted from OpenFNB58
import QtQuick
import QtQuick.Controls.Material

Item {
    id: root

    property string title:     ""
    property string leftUnit:  ""
    property string rightUnit: ""

    property real effectiveWindowSecs: 60
    property real viewLeft:  0
    property bool followMode: true

    property real selectionStart: -1
    property real selectionEnd:   -1
    signal rangeSelected(real tStart, real tEnd)
    signal selectionCleared
    signal viewChanged(real newViewLeft, real newWindowSecs)

    property var  seriesList: []
    property real leftYMin:  0.0
    property real leftYMax:  1.0
    property real rightYMin: 0.0
    property real rightYMax: 0.1
    property real xHead:     0.0

    function appendTo(idx, x, y) {
        if (idx < 0 || idx >= seriesList.length) return
        var s = seriesList[idx]
        s.data.push({ x: x, y: y })
        if (s.data.length > 8000) s.data.splice(0, s.data.length - 8000)
        if (x > xHead) xHead = x
        if (s.yAxis === "left") {
            if (y > leftYMax)  leftYMax  = y * 1.25 + 0.1
            if (y < leftYMin)  leftYMin  = y * 0.9
        } else {
            if (y > rightYMax) rightYMax = y * 1.25 + 0.01
        }
        canvas.requestPaint()
    }

    function clearAll() {
        for (var i = 0; i < seriesList.length; i++) seriesList[i].data = []
        leftYMin = 0; leftYMax = 1.0; rightYMin = 0; rightYMax = 0.1; xHead = 0.0
        selectionStart = -1; selectionEnd = -1
        canvas.requestPaint()
    }

    function currentViewLeft() {
        if (followMode) return Math.max(0, xHead - effectiveWindowSecs + 0.5)
        return Math.max(0, viewLeft)
    }

    // Public repaint request — call this instead of accessing canvas directly.
    function repaint() { canvas.requestPaint() }

    function pixelToTime(px) {
        var w = width - mL - mR
        if (w <= 0) return 0
        return currentViewLeft() + Math.max(0, Math.min(1, (px - mL) / w)) * effectiveWindowSecs
    }

    readonly property int mL: 62
    readonly property int mR: rightUnit !== "" ? 62 : 12
    readonly property int mT: 28
    readonly property int mB: 36

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.Image

        onPaint: {
            var ctx = getContext("2d")
            var W = width, H = height
            ctx.clearRect(0, 0, W, H)
            var pX = root.mL, pY = root.mT
            var pW = W - root.mL - root.mR
            var pH = H - root.mT - root.mB
            if (pW < 10 || pH < 10) return

            var xStart = root.currentViewLeft()
            var xEnd   = xStart + root.effectiveWindowSecs

            // Background
            ctx.fillStyle = "#0d1b2e"
            ctx.fillRect(pX, pY, pW, pH)

            // Grid
            var nGX = 8, nGY = 5
            ctx.strokeStyle = "#1a3060"
            ctx.lineWidth = 1
            for (var i = 0; i <= nGX; i++) {
                var gx = pX + i * pW / nGX
                ctx.beginPath(); ctx.moveTo(gx, pY); ctx.lineTo(gx, pY + pH); ctx.stroke()
            }
            for (var j = 0; j <= nGY; j++) {
                var gy = pY + j * pH / nGY
                ctx.beginPath(); ctx.moveTo(pX, gy); ctx.lineTo(pX + pW, gy); ctx.stroke()
            }

            var lYMin = root.leftYMin,  lYMax = root.leftYMax
            var rYMin = root.rightYMin, rYMax = root.rightYMax
            var safeL = (lYMax - lYMin) < 0.001 ? 1 : (lYMax - lYMin)
            var safeR = (rYMax - rYMin) < 0.00001 ? 1 : (rYMax - rYMin)

            function mx(x)  { return pX + (x - xStart) / (xEnd - xStart) * pW }
            function myL(y) { return pY + pH - (y - lYMin) / safeL * pH }
            function myR(y) { return pY + pH - (y - rYMin) / safeR * pH }

            ctx.save(); ctx.beginPath(); ctx.rect(pX, pY, pW, pH); ctx.clip()

            // Selection highlight
            var sSt = root.selectionStart, sEn = root.selectionEnd
            if (sSt >= 0 && sEn >= 0) {
                var sxA = mx(Math.min(sSt, sEn)), sxB = mx(Math.max(sSt, sEn))
                if (sxB > sxA) {
                    ctx.fillStyle = "rgba(100,180,255,0.10)"; ctx.fillRect(sxA, pY, sxB - sxA, pH)
                    ctx.strokeStyle = "rgba(100,180,255,0.55)"; ctx.lineWidth = 1
                    ctx.setLineDash([4, 3])
                    ctx.beginPath(); ctx.moveTo(sxA, pY); ctx.lineTo(sxA, pY + pH); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(sxB, pY); ctx.lineTo(sxB, pY + pH); ctx.stroke()
                    ctx.setLineDash([])
                }
            }

            // Series
            for (var si = 0; si < root.seriesList.length; si++) {
                var s = root.seriesList[si], data = s.data
                if (data.length < 2) continue
                var mapY = (s.yAxis === "right") ? myR : myL
                var margin = (xEnd - xStart) / pW

                if (s.fillArea) {
                    ctx.beginPath()
                    var fa = true, lpx2 = 0
                    for (var k = 0; k < data.length; k++) {
                        if (data[k].x < xStart - margin || data[k].x > xEnd + margin) continue
                        var fpx = mx(data[k].x), fpy = mapY(data[k].y)
                        if (fa) { ctx.moveTo(fpx, mapY(0)); ctx.lineTo(fpx, fpy); fa = false }
                        else ctx.lineTo(fpx, fpy); lpx2 = fpx
                    }
                    if (!fa) {
                        ctx.lineTo(lpx2, mapY(0)); ctx.closePath()
                        ctx.fillStyle = s.fillColor || Qt.rgba(1, 1, 1, 0.06); ctx.fill()
                    }
                }

                ctx.beginPath(); var fl = true
                for (var k2 = 0; k2 < data.length; k2++) {
                    if (data[k2].x < xStart - margin || data[k2].x > xEnd + margin) continue
                    var lpx = mx(data[k2].x), lpy = mapY(data[k2].y)
                    if (fl) { ctx.moveTo(lpx, lpy); fl = false } else ctx.lineTo(lpx, lpy)
                }
                ctx.strokeStyle = s.color
                ctx.lineWidth   = s.yAxis === "right" ? 1.5 : 2
                ctx.setLineDash(s.yAxis === "right" ? [4, 3] : [])
                ctx.stroke(); ctx.setLineDash([])
            }
            ctx.restore()

            // Border
            ctx.strokeStyle = "#2a4070"; ctx.lineWidth = 1
            ctx.strokeRect(pX, pY, pW, pH)

            // X axis labels
            ctx.fillStyle = "#99aabb"; ctx.font = "11px monospace"
            ctx.textAlign = "center"; ctx.textBaseline = "top"
            for (var i2 = 0; i2 <= nGX; i2++) {
                var gx2 = pX + i2 * pW / nGX
                var xv  = xStart + i2 * (xEnd - xStart) / nGX
                ctx.fillText(xv.toFixed(0), gx2, pY + pH + 4)
            }
            ctx.fillText(qsTr("Time (s)"), pX + pW / 2, pY + pH + 20)

            // Selection time labels
            if (sSt >= 0 && sEn >= 0) {
                ctx.fillStyle = "rgba(130,200,255,0.85)"; ctx.font = "10px monospace"
                ctx.textBaseline = "bottom"; ctx.textAlign = "center"
                var t0l = Math.min(sSt, sEn), t1l = Math.max(sSt, sEn)
                var sxA2 = mx(t0l), sxB2 = mx(t1l)
                if (sxA2 >= pX && sxA2 <= pX + pW) ctx.fillText(t0l.toFixed(1) + "s", sxA2, pY - 2)
                if (sxB2 >= pX && sxB2 <= pX + pW) ctx.fillText(t1l.toFixed(1) + "s", sxB2, pY - 2)
            }

            // Left Y axis labels
            ctx.fillStyle = "#99aabb"; ctx.font = "11px monospace"
            ctx.textAlign = "right"; ctx.textBaseline = "middle"
            for (var j2 = 0; j2 <= nGY; j2++) {
                var gy2 = pY + (nGY - j2) * pH / nGY
                var yv  = lYMin + j2 * (lYMax - lYMin) / nGY
                var yvStr = yv < 10 ? yv.toFixed(3) : yv.toFixed(1)
                ctx.fillText(yvStr, pX - 4, gy2)
            }
            if (root.leftUnit !== "") {
                ctx.save(); ctx.translate(11, pY + pH / 2); ctx.rotate(-Math.PI / 2)
                ctx.textAlign = "center"; ctx.font = "11px sans-serif"; ctx.fillStyle = "#bbccdd"
                ctx.fillText(root.leftUnit, 0, 0); ctx.restore()
            }

            // Right Y axis labels
            if (root.rightUnit !== "") {
                ctx.textAlign = "left"; ctx.textBaseline = "middle"
                for (var j3 = 0; j3 <= nGY; j3++) {
                    var gy3 = pY + (nGY - j3) * pH / nGY
                    var rv  = rYMin + j3 * (rYMax - rYMin) / nGY
                    ctx.fillStyle = "#99aabb"
                    ctx.fillText(rv < 10 ? rv.toFixed(3) : rv.toFixed(1), pX + pW + 4, gy3)
                }
                ctx.save(); ctx.translate(W - 11, pY + pH / 2); ctx.rotate(Math.PI / 2)
                ctx.textAlign = "center"; ctx.font = "11px sans-serif"; ctx.fillStyle = "#bbccdd"
                ctx.fillText(root.rightUnit, 0, 0); ctx.restore()
            }

            // Title + legend
            ctx.fillStyle = "#dde8f8"; ctx.font = "bold 12px sans-serif"
            ctx.textAlign = "left"; ctx.textBaseline = "top"
            ctx.fillText(root.title, pX + 4, 6)
            var legX = pX + pW / 2 - 20, legY = 8
            ctx.textBaseline = "middle"; ctx.font = "11px sans-serif"
            for (var si2 = 0; si2 < root.seriesList.length; si2++) {
                var ser = root.seriesList[si2]
                ctx.fillStyle = ser.color; ctx.fillRect(legX, legY - 1, 14, 2)
                ctx.fillStyle = "#bbccdd"; ctx.fillText(ser.name, legX + 18, legY)
                legX += ctx.measureText(ser.name).width + 38
            }

            // Hint
            ctx.fillStyle = "rgba(153,170,187,0.25)"; ctx.font = "10px sans-serif"
            ctx.textAlign = "right"; ctx.textBaseline = "bottom"
            ctx.fillText(qsTr("pinch=zoom  2-finger=pan  drag=measure"), pX + pW - 4, pY + pH - 4)
        }
    }

    // ── Internal zoom/pan helper ──────────────────────────────────────────
    // Emits viewChanged (for external consumers to sync their state) and then
    // immediately repaints — without requestPaint() the canvas won't redraw
    // until the next data sample arrives, making zoom/pan feel broken.
    function _applyViewChange(newVl, newWs) {
        root.viewChanged(newVl, newWs)
        canvas.requestPaint()
    }

    // ── Mouse wheel zoom (desktop / touchpad) ─────────────────────────────
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            var factor = event.angleDelta.y > 0 ? 0.75 : 1.33
            var ws   = root.effectiveWindowSecs
            var vl   = root.currentViewLeft()
            var pW   = Math.max(1, root.width - root.mL - root.mR)
            var frac = Math.max(0, Math.min(1, (point.position.x - root.mL) / pW))
            var mouseT = vl + frac * ws
            var newWs  = Math.max(2, Math.min(7200, ws * factor))
            var newVl  = Math.max(0, mouseT - frac * newWs)
            root._applyViewChange(newVl, newWs)
        }
    }

    // ── Pinch: zoom + two-finger pan (touch) ──────────────────────────────
    // grabPermissions: CanTakeOverFromAnything — essential on Android so that
    // PinchHandler can steal touch points from DragHandler when a 2nd finger lands.
    PinchHandler {
        id: pinchHandler
        target: null
        minimumPointCount: 2
        maximumPointCount: 2
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        property real _startWs: 60
        property real _startVl: 0
        property real _startCx: 0

        onActiveChanged: {
            if (active) {
                _startWs = root.effectiveWindowSecs
                _startVl = root.currentViewLeft()
                _startCx = centroid.position.x
                // Cancel any in-progress selection when pinch begins
                root.selectionStart = -1
                root.selectionEnd   = -1
            }
        }
        onActiveScaleChanged: {
            var pW   = Math.max(1, root.width - root.mL - root.mR)
            var frac = Math.max(0, Math.min(1, (centroid.position.x - root.mL) / pW))
            var pinchT = _startVl + frac * _startWs
            var newWs  = Math.max(2, Math.min(7200, _startWs / activeScale))
            var panDt  = -(centroid.position.x - _startCx) / pW * _startWs
            var newVl  = Math.max(0, pinchT - frac * newWs + panDt)
            root._applyViewChange(newVl, newWs)
        }
    }

    // ── Single-finger drag: range selection (touch + LMB on desktop) ──────
    DragHandler {
        id: selectionDrag
        target: null
        acceptedButtons: Qt.LeftButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen
        dragThreshold: 4
        // Allow PinchHandler to take over when a second finger arrives
        grabPermissions: PointerHandler.CanTakeOverFromHandlersOfSameType |
                         PointerHandler.ApprovesTakeOverByAnything

        onActiveChanged: {
            if (active) {
                root.selectionStart = root.pixelToTime(centroid.pressPosition.x)
                root.selectionEnd   = root.selectionStart
                canvas.requestPaint()
            } else {
                var t0 = Math.min(root.selectionStart, root.selectionEnd)
                var t1 = Math.max(root.selectionStart, root.selectionEnd)
                if (t1 - t0 > 0.1) root.rangeSelected(t0, t1)
                canvas.requestPaint()
            }
        }
        onCentroidChanged: {
            if (active) {
                root.selectionEnd = root.pixelToTime(centroid.position.x)
                canvas.requestPaint()
            }
        }
    }

    // ── RMB drag: pan (desktop only) ──────────────────────────────────────
    DragHandler {
        id: panDrag
        target: null
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse

        property real _startVL: 0

        onActiveChanged: {
            if (active) _startVL = root.currentViewLeft()
        }
        onCentroidChanged: {
            if (active) {
                var pW = Math.max(1, root.width - root.mL - root.mR)
                var dt = -(centroid.position.x - centroid.pressPosition.x) / pW * root.effectiveWindowSecs
                root._applyViewChange(Math.max(0, _startVL + dt), root.effectiveWindowSecs)
            }
        }
    }

    // ── Double-tap / double-click: clear selection ────────────────────────
    TapHandler {
        acceptedButtons: Qt.LeftButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchScreen
        gesturePolicy: TapHandler.WithinBounds

        onDoubleTapped: {
            root.selectionStart = -1
            root.selectionEnd   = -1
            canvas.requestPaint()
            root.selectionCleared()
        }
    }
}
