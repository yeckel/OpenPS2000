// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

// ── PulseChart ────────────────────────────────────────────────────────────────
// Scrolling dual-axis canvas chart for the pulse waveform.
// Voltage = cyan (left axis), Current = orange (right axis).
Canvas {
    id: canvas
    antialiasing: true

    // Public interface
    function addPoint(t, v, i) {
        pts.push({ t: t, v: v, i: i })
        requestPaint()
    }
    function clearAll() {
        pts = []
        requestPaint()
    }
    function clearVertical() {
        requestPaint()
    }

    property var pts: []

    onPaint: {
        var ctx = getContext("2d")
        var W = width, H = height
        if (W <= 0 || H <= 0) return

        ctx.fillStyle = "#0d1117"
        ctx.fillRect(0, 0, W, H)

        if (pts.length < 2) {
            // empty state hint
            ctx.fillStyle = "#2a3a4a"
            ctx.font = "14px sans-serif"
            ctx.textAlign = "center"
            ctx.fillText(qsTr("Start the generator to see the waveform"), W / 2, H / 2)
            return
        }

        var padL = 52, padR = 52, padT = 16, padB = 36
        var cW = W - padL - padR
        var cH = H - padT - padB

        // ── Data ranges ──────────────────────────────────────────────────────
        var tMin = pts[0].t
        var tMax = pts[pts.length - 1].t
        var tSpan = Math.max(tMax - tMin, 0.001)

        var vMax = 0, iMax = 0
        for (var p of pts) {
            vMax = Math.max(vMax, p.v)
            iMax = Math.max(iMax, p.i)
        }
        vMax = Math.max(vMax * 1.15, 0.1)
        iMax = Math.max(iMax * 1.15, 0.001)

        function xOf(t)  { return padL + (t - tMin) / tSpan * cW }
        function yOfV(v) { return padT + (1 - v / vMax) * cH }
        function yOfI(i) { return padT + (1 - i / iMax) * cH }

        // ── Grid ─────────────────────────────────────────────────────────────
        ctx.strokeStyle = "#1a2a3a"
        ctx.lineWidth = 1
        for (var gi = 1; gi < 5; gi++) {
            var gy = padT + gi * cH / 5
            ctx.beginPath(); ctx.moveTo(padL, gy); ctx.lineTo(padL + cW, gy); ctx.stroke()
        }
        for (var gj = 1; gj < 8; gj++) {
            var gx = padL + gj * cW / 8
            ctx.beginPath(); ctx.moveTo(gx, padT); ctx.lineTo(gx, padT + cH); ctx.stroke()
        }

        // ── Voltage line (step/square wave) ──────────────────────────────────
        ctx.strokeStyle = "#00e5ff"
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.moveTo(xOf(pts[0].t), yOfV(pts[0].v))
        for (var vi = 1; vi < pts.length; vi++) {
            // Step: draw horizontal to this x at previous y, then vertical
            ctx.lineTo(xOf(pts[vi].t), yOfV(pts[vi - 1].v))
            ctx.lineTo(xOf(pts[vi].t), yOfV(pts[vi].v))
        }
        ctx.stroke()

        // ── Current line ─────────────────────────────────────────────────────
        ctx.strokeStyle = "#ff9800"
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.moveTo(xOf(pts[0].t), yOfI(pts[0].i))
        for (var ii = 1; ii < pts.length; ii++) {
            ctx.lineTo(xOf(pts[ii].t), yOfI(pts[ii - 1].i))
            ctx.lineTo(xOf(pts[ii].t), yOfI(pts[ii].i))
        }
        ctx.stroke()

        // ── Axes ─────────────────────────────────────────────────────────────
        ctx.strokeStyle = "#3a4a5a"; ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(padL, padT); ctx.lineTo(padL, padT + cH)
        ctx.lineTo(padL + cW, padT + cH); ctx.lineTo(padL + cW, padT)
        ctx.stroke()

        // ── Left axis labels (V) ─────────────────────────────────────────────
        ctx.fillStyle = "#00e5ff"; ctx.font = "10px monospace"; ctx.textAlign = "right"
        for (var li = 0; li <= 5; li++) {
            var lv = vMax * li / 5
            var ly = yOfV(lv)
            ctx.fillText(lv.toFixed(1) + "V", padL - 4, ly + 4)
        }

        // ── Right axis labels (I) ────────────────────────────────────────────
        ctx.fillStyle = "#ff9800"; ctx.textAlign = "left"
        for (var ri = 0; ri <= 5; ri++) {
            var riv = iMax * ri / 5
            var ry = yOfI(riv)
            var rLabel = riv < 1 ? (riv * 1000).toFixed(0) + "mA" : riv.toFixed(2) + "A"
            ctx.fillText(rLabel, padL + cW + 4, ry + 4)
        }

        // ── Time axis labels ──────────────────────────────────────────────────
        ctx.fillStyle = "#8899aa"; ctx.font = "10px monospace"; ctx.textAlign = "center"
        for (var ti = 0; ti <= 8; ti++) {
            var tv = tMin + tSpan * ti / 8
            var tx = padL + cW * ti / 8
            ctx.fillText(tv.toFixed(1) + "s", tx, padT + cH + 22)
        }

        // ── Legend ────────────────────────────────────────────────────────────
        ctx.fillStyle = "#00e5ff"; ctx.textAlign = "left"; ctx.font = "11px sans-serif"
        ctx.fillText("── " + qsTr("Voltage"), padL + 8, padT + 14)
        ctx.fillStyle = "#ff9800"
        ctx.fillText("── " + qsTr("Current"), padL + 120, padT + 14)
    }
}
