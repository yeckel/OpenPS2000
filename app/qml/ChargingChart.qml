// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick

Canvas {
    id: root

    // ── Public API ──────────────────────────────────────────────────────────
    function addPoint(tSec, v, i) {
        voltData.push({t: tSec, v: v})
        currData.push({t: tSec, i: i})
        requestPaint()
    }

    function addPhaseMarker(tSec, stateInt, label) {
        var colors = ["", "#4dc8ff", "#ff9940", "#44cc88", "#44ff90", "#ff4444"]
        phaseMarkers.push({t: tSec, label: label, color: colors[stateInt] || "#ffffff"})
        requestPaint()
    }

    function clearAll() {
        voltData = []
        currData = []
        phaseMarkers = []
        requestPaint()
    }

    // ── Internal data ───────────────────────────────────────────────────────
    property var voltData:     []
    property var currData:     []
    property var phaseMarkers: []

    // ── Canvas paint ────────────────────────────────────────────────────────
    onPaint: {
        var ctx = getContext("2d")
        var W = width, H = height

        // ── Layout constants ─────────────────────────────────────────────
        var padL = 52, padR = 52, padT = 28, padB = 44
        var pW = W - padL - padR
        var pH = H - padT - padB

        // ── Background ───────────────────────────────────────────────────
        ctx.fillStyle = "#0d1117"
        ctx.fillRect(0, 0, W, H)

        // ── Empty state hint ─────────────────────────────────────────────
        if (voltData.length < 2) {
            ctx.fillStyle = "#334455"
            ctx.font = "14px sans-serif"
            ctx.textAlign = "center"
            ctx.fillText(qsTr("Charging curve will appear here"), W / 2, H / 2)
            drawAxes(ctx, padL, padT, pW, pH, 0, 1, 0, 1, 0, 1)
            return
        }

        // ── Compute ranges ───────────────────────────────────────────────
        var tMax = 0, vMax = 0, vMin = 1e9, iMax = 0
        for (var k = 0; k < voltData.length; k++) {
            tMax = Math.max(tMax, voltData[k].t)
            vMax = Math.max(vMax, voltData[k].v)
            vMin = Math.min(vMin, voltData[k].v)
        }
        for (var m = 0; m < currData.length; m++) {
            iMax = Math.max(iMax, currData[m].i)
        }
        tMax = Math.max(tMax, 60)          // min 1 minute
        vMax = vMax * 1.08
        vMin = Math.max(0, vMin * 0.92)
        iMax = iMax * 1.15 || 0.1

        // Convert to minutes for display
        var tMaxMin = tMax / 60.0

        // ── Grid ─────────────────────────────────────────────────────────
        ctx.strokeStyle = "#1e2a3e"
        ctx.lineWidth = 1
        var gridX = 5, gridY = 4
        for (var gx = 0; gx <= gridX; gx++) {
            var x = padL + gx * pW / gridX
            ctx.beginPath(); ctx.moveTo(x, padT); ctx.lineTo(x, padT + pH); ctx.stroke()
        }
        for (var gy = 0; gy <= gridY; gy++) {
            var y = padT + gy * pH / gridY
            ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(padL + pW, y); ctx.stroke()
        }

        // ── Phase markers ────────────────────────────────────────────────
        for (var pm = 0; pm < phaseMarkers.length; pm++) {
            var marker = phaseMarkers[pm]
            var mx = padL + (marker.t / tMax) * pW
            ctx.strokeStyle = marker.color
            ctx.setLineDash([6, 4])
            ctx.lineWidth = 1.5
            ctx.beginPath(); ctx.moveTo(mx, padT); ctx.lineTo(mx, padT + pH); ctx.stroke()
            ctx.setLineDash([])
            ctx.fillStyle = marker.color
            ctx.font = "11px sans-serif"
            ctx.textAlign = "center"
            ctx.fillText(marker.label, mx, padT - 6)
        }

        // ── Voltage series (left axis, cyan) ─────────────────────────────
        ctx.strokeStyle = "#4dc8ff"
        ctx.lineWidth = 2
        ctx.setLineDash([])
        ctx.beginPath()
        for (var vi = 0; vi < voltData.length; vi++) {
            var vx = padL + (voltData[vi].t / tMax) * pW
            var vy = padT + pH - ((voltData[vi].v - vMin) / (vMax - vMin)) * pH
            if (vi === 0) ctx.moveTo(vx, vy); else ctx.lineTo(vx, vy)
        }
        ctx.stroke()

        // ── Current series (right axis, orange) ──────────────────────────
        ctx.strokeStyle = "#ff9940"
        ctx.lineWidth = 2
        ctx.beginPath()
        for (var ci = 0; ci < currData.length; ci++) {
            var cx2 = padL + (currData[ci].t / tMax) * pW
            var cy2 = padT + pH - (currData[ci].i / iMax) * pH
            if (ci === 0) ctx.moveTo(cx2, cy2); else ctx.lineTo(cx2, cy2)
        }
        ctx.stroke()

        // ── Axes + labels ─────────────────────────────────────────────────
        drawAxes(ctx, padL, padT, pW, pH, tMaxMin, vMin, vMax, iMax, gridX, gridY)

        // ── Legend ────────────────────────────────────────────────────────
        var lx = padL + pW - 140, ly = padT + 12
        ctx.fillStyle = "rgba(13,17,23,0.75)"
        ctx.fillRect(lx - 6, ly - 14, 140, 46)
        ctx.fillStyle = "#4dc8ff"
        ctx.fillRect(lx, ly, 20, 3)
        ctx.fillStyle = "#ccddee"
        ctx.font = "12px sans-serif"; ctx.textAlign = "left"
        ctx.fillText(qsTr("Voltage (V)"), lx + 26, ly + 4)
        ctx.fillStyle = "#ff9940"
        ctx.fillRect(lx, ly + 18, 20, 3)
        ctx.fillStyle = "#ccddee"
        ctx.fillText(qsTr("Current (A)"), lx + 26, ly + 22)
    }

    // ── Axes helper ─────────────────────────────────────────────────────────
    function drawAxes(ctx, padL, padT, pW, pH, tMaxMin, vMin, vMax, iMax, gridX, gridY) {
        ctx.strokeStyle = "#2a3a50"
        ctx.lineWidth = 1
        ctx.setLineDash([])
        ctx.beginPath()
        ctx.moveTo(padL, padT); ctx.lineTo(padL, padT + pH)
        ctx.moveTo(padL, padT + pH); ctx.lineTo(padL + pW, padT + pH)
        ctx.moveTo(padL + pW, padT); ctx.lineTo(padL + pW, padT + pH)
        ctx.stroke()

        ctx.fillStyle = "#8899aa"
        ctx.font = "11px sans-serif"

        // X axis labels (time in minutes)
        ctx.textAlign = "center"
        for (var gx = 0; gx <= gridX; gx++) {
            var tx = tMaxMin * gx / gridX
            var px = padL + gx * pW / gridX
            ctx.fillText(tx.toFixed(tx < 10 ? 1 : 0) + "m", px, padT + pH + 16)
        }

        // Left Y axis: voltage
        ctx.textAlign = "right"
        for (var gy = 0; gy <= 4; gy++) {
            var vv = vMin + (vMax - vMin) * (4 - gy) / 4
            var py = padT + gy * pH / 4
            ctx.fillText(vv.toFixed(1), padL - 6, py + 4)
        }

        // Right Y axis: current
        ctx.textAlign = "left"
        for (var gi = 0; gi <= 4; gi++) {
            var iv = iMax * (4 - gi) / 4
            var pyi = padT + gi * pH / 4
            ctx.fillText(iv.toFixed(2), padL + pW + 6, pyi + 4)
        }

        // Axis titles
        ctx.fillStyle = "#4dc8ff"
        ctx.font = "11px sans-serif"
        ctx.textAlign = "center"
        ctx.save()
        ctx.translate(12, padT + pH / 2)
        ctx.rotate(-Math.PI / 2)
        ctx.fillText(qsTr("Voltage (V)"), 0, 0)
        ctx.restore()

        ctx.fillStyle = "#ff9940"
        ctx.save()
        ctx.translate(padL + pW + 44, padT + pH / 2)
        ctx.rotate(-Math.PI / 2)
        ctx.fillText(qsTr("Current (A)"), 0, 0)
        ctx.restore()

        ctx.fillStyle = "#8899aa"
        ctx.textAlign = "center"
        ctx.fillText(qsTr("Time (min)"), padL + pW / 2, padT + pH + 34)
    }
}
