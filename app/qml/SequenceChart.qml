// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls

// ── SequenceChart ─────────────────────────────────────────────────────────────
// Dual-axis canvas chart. Actual V=cyan/I=orange (solid).
// Planned V=cyan/I=orange (dashed). Time axis = seconds.
Canvas {
    id: canvas
    antialiasing: true

    property var actualPts:  []   // {t, v, i}
    property var plannedPts: []   // {t, v, i}

    function addActual(t, v, i)  { actualPts.push({t,v,i});  requestPaint() }
    function addPlanned(t, v, i) { plannedPts.push({t,v,i}); requestPaint() }
    function clearAll()          { actualPts = []; plannedPts = []; requestPaint() }

    onPaint: {
        var ctx = getContext("2d")
        var W = width, H = height
        if (W <= 0 || H <= 0) return
        ctx.fillStyle = "#0d1117"
        ctx.fillRect(0, 0, W, H)

        var allPts = actualPts.concat(plannedPts)
        if (allPts.length < 1) {
            ctx.fillStyle = "#2a3a4a"; ctx.font = "14px sans-serif"; ctx.textAlign = "center"
            ctx.fillText(qsTr("Start the sequence to see the chart"), W/2, H/2)
            return
        }

        var padL = 52, padR = 56, padT = 20, padB = 36
        var cW = W - padL - padR, cH = H - padT - padB

        // ── Ranges ───────────────────────────────────────────────────────────
        var tMax = 0, vMax = 0, iMax = 0
        for (var p of allPts) {
            tMax = Math.max(tMax, p.t)
            vMax = Math.max(vMax, p.v)
            iMax = Math.max(iMax, p.i)
        }
        tMax = Math.max(tMax * 1.05, 1)
        vMax = Math.max(vMax * 1.15, 0.1)
        iMax = Math.max(iMax * 1.15, 0.001)

        function xOf(t)  { return padL + (t / tMax) * cW }
        function yOfV(v) { return padT + (1 - v / vMax) * cH }
        function yOfI(i) { return padT + (1 - i / iMax) * cH }

        // ── Grid ─────────────────────────────────────────────────────────────
        ctx.strokeStyle = "#1a2a3a"; ctx.lineWidth = 1
        for (var gi = 1; gi < 5; gi++) {
            var gy = padT + gi * cH / 5
            ctx.beginPath(); ctx.moveTo(padL, gy); ctx.lineTo(padL+cW, gy); ctx.stroke()
        }
        for (var gj = 1; gj < 8; gj++) {
            var gx = padL + gj * cW / 8
            ctx.beginPath(); ctx.moveTo(gx, padT); ctx.lineTo(gx, padT+cH); ctx.stroke()
        }

        // ── Helper: draw a polyline ───────────────────────────────────────────
        function drawLine(pts, xFn, yFn, color, dashed, width) {
            if (pts.length < 2) return
            ctx.strokeStyle = color; ctx.lineWidth = width
            if (dashed) ctx.setLineDash([6, 4])
            else        ctx.setLineDash([])
            ctx.beginPath()
            ctx.moveTo(xFn(pts[0]), yFn(pts[0]))
            for (var k = 1; k < pts.length; k++)
                ctx.lineTo(xFn(pts[k]), yFn(pts[k]))
            ctx.stroke()
            ctx.setLineDash([])
        }

        // ── Planned (dashed) ─────────────────────────────────────────────────
        drawLine(plannedPts, p => xOf(p.t), p => yOfV(p.v), "#005577", true, 1.5)
        drawLine(plannedPts, p => xOf(p.t), p => yOfI(p.i), "#774400", true, 1.5)

        // ── Actual (solid) ───────────────────────────────────────────────────
        drawLine(actualPts, p => xOf(p.t), p => yOfV(p.v), "#00e5ff", false, 2)
        drawLine(actualPts, p => xOf(p.t), p => yOfI(p.i), "#ff9800", false, 2)

        // ── Axes ─────────────────────────────────────────────────────────────
        ctx.strokeStyle = "#3a4a5a"; ctx.lineWidth = 1; ctx.setLineDash([])
        ctx.beginPath()
        ctx.moveTo(padL, padT); ctx.lineTo(padL, padT+cH)
        ctx.lineTo(padL+cW, padT+cH); ctx.lineTo(padL+cW, padT)
        ctx.stroke()

        // ── V axis (left) ────────────────────────────────────────────────────
        ctx.fillStyle = "#00e5ff"; ctx.font = "10px monospace"; ctx.textAlign = "right"
        for (var li = 0; li <= 5; li++) {
            var lv = vMax * li / 5
            ctx.fillText(lv.toFixed(1) + "V", padL-4, yOfV(lv)+4)
        }

        // ── I axis (right) ───────────────────────────────────────────────────
        ctx.fillStyle = "#ff9800"; ctx.textAlign = "left"
        for (var ri = 0; ri <= 5; ri++) {
            var riv = iMax * ri / 5
            var rl = riv < 1 ? (riv*1000).toFixed(0)+"mA" : riv.toFixed(2)+"A"
            ctx.fillText(rl, padL+cW+4, yOfI(riv)+4)
        }

        // ── Time axis ────────────────────────────────────────────────────────
        ctx.fillStyle = "#8899aa"; ctx.font = "10px monospace"; ctx.textAlign = "center"
        for (var ti = 0; ti <= 8; ti++) {
            var tv = tMax * ti / 8
            ctx.fillText(tv.toFixed(1)+"s", padL + cW*ti/8, padT+cH+22)
        }

        // ── Legend ────────────────────────────────────────────────────────────
        ctx.font = "11px sans-serif"; ctx.textAlign = "left"
        ctx.fillStyle = "#00e5ff"
        ctx.fillText("── " + qsTr("V actual"),  padL+8,   padT+14)
        ctx.fillStyle = "#ff9800"
        ctx.fillText("── " + qsTr("I actual"),  padL+110, padT+14)
        ctx.fillStyle = "#005577"
        ctx.fillText("- - " + qsTr("V planned"), padL+210, padT+14)
        ctx.fillStyle = "#774400"
        ctx.fillText("- - " + qsTr("I planned"), padL+330, padT+14)
    }
}
