// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "PS2000Protocol.h"

#include <QtEndian>
#include <cstring>
#include <cmath>

namespace PS2000 {

// ── Checksum ──────────────────────────────────────────────────────────────
uint16_t checksum(const QByteArray& data)
{
    uint16_t sum = 0;
    for (unsigned char b : data) sum += b;
    return sum;
}

// ── Telegram builders ─────────────────────────────────────────────────────
QByteArray buildQuery(uint8_t obj, uint8_t dn, int expectedDataLen)
{
    // SD = Query(0x40) | Cast(0x20) | PC→Dev(0x10) | (expectedDataLen-1)
    uint8_t sd = static_cast<uint8_t>(
        SD_QUERY | SD_CAST | SD_PC2DEV | ((expectedDataLen - 1) & 0x0F));

    QByteArray buf;
    buf.reserve(5);
    buf += static_cast<char>(sd);
    buf += static_cast<char>(dn);
    buf += static_cast<char>(obj);
    uint16_t cs = checksum(buf);
    buf += static_cast<char>((cs >> 8) & 0xFF);
    buf += static_cast<char>(cs & 0xFF);
    return buf;
}

QByteArray buildSend(uint8_t obj, uint8_t dn, const QByteArray& data)
{
    int dataLen = data.size();
    // SD = Send(0xC0) | Cast(0x20) | PC→Dev(0x10) | (dataLen-1)
    uint8_t sd = static_cast<uint8_t>(
        SD_SEND | SD_CAST | SD_PC2DEV | ((dataLen - 1) & 0x0F));

    QByteArray buf;
    buf.reserve(3 + dataLen + 2);
    buf += static_cast<char>(sd);
    buf += static_cast<char>(dn);
    buf += static_cast<char>(obj);
    buf += data;
    uint16_t cs = checksum(buf);
    buf += static_cast<char>((cs >> 8) & 0xFF);
    buf += static_cast<char>(cs & 0xFF);
    return buf;
}

QByteArray buildControl(uint8_t dn, uint8_t mask, uint8_t value)
{
    // Object 54: data = [mask, value]
    QByteArray data;
    data += static_cast<char>(mask);
    data += static_cast<char>(value);
    return buildSend(OBJ_CONTROL, dn, data);
}

QByteArray buildSetInt(uint8_t obj, uint8_t dn, uint16_t rawValue)
{
    QByteArray data;
    data += static_cast<char>((rawValue >> 8) & 0xFF);
    data += static_cast<char>(rawValue & 0xFF);
    return buildSend(obj, dn, data);
}

// ── Response parser ───────────────────────────────────────────────────────
int responseTotalLen(uint8_t sd)
{
    int dataLen = (sd & 0x0F) + 1;
    return 3 + dataLen + 2;  // SD + DN + OBJ + DATA[n] + CS[2]
}

bool parseResponse(const QByteArray& raw, uint8_t& obj, QByteArray& data)
{
    if (raw.size() < 5) return false;

    uint8_t sd = static_cast<uint8_t>(raw[0]);

    // Must be an answer (bits 7:6 = 10 = 0x80)
    if ((sd & 0xC0) != SD_ANSWER) return false;

    int dataLen    = (sd & 0x0F) + 1;
    int totalLen   = 3 + dataLen + 2;
    if (raw.size() < totalLen) return false;

    obj = static_cast<uint8_t>(raw[2]);
    data = raw.mid(3, dataLen);

    // Verify checksum
    uint16_t cs = checksum(raw.left(totalLen - 2));
    uint8_t  csHi = static_cast<uint8_t>(raw[totalLen - 2]);
    uint8_t  csLo = static_cast<uint8_t>(raw[totalLen - 1]);
    uint16_t expected = static_cast<uint16_t>((csHi << 8) | csLo);

    return cs == expected;
}

// ── Status parsers ────────────────────────────────────────────────────────
DeviceStatus parseStatus(const QByteArray& data, float nomVoltage, float nomCurrent)
{
    DeviceStatus s;
    if (data.size() < 6) return s;

    uint8_t sb0 = static_cast<uint8_t>(data[0]);
    uint8_t sb1 = static_cast<uint8_t>(data[1]);

    s.remoteMode = (sb0 & SB0_REMOTE) != 0;
    s.outputOn   = (sb1 & SB1_OUTPUT_ON) != 0;
    s.ccMode     = ((sb1 & SB1_REG_MASK) == SB1_CC);
    s.ovpActive  = (sb1 & SB1_OVP) != 0;
    s.ocpActive  = (sb1 & SB1_OCP) != 0;
    s.oppActive  = (sb1 & SB1_OPP) != 0;
    s.otpActive  = (sb1 & SB1_OTP) != 0;

    uint16_t rawV = parseUint16BE(data, 2);
    uint16_t rawI = parseUint16BE(data, 4);

    s.voltage = fromRaw(rawV, nomVoltage);
    s.current = fromRaw(rawI, nomCurrent);
    s.power   = s.voltage * s.current;

    return s;
}

DeviceStatus parseStatusSet(const QByteArray& data, float nomVoltage, float nomCurrent)
{
    DeviceStatus s = parseStatus(data, nomVoltage, nomCurrent);
    // obj 72 has same structure but words represent set values
    if (data.size() >= 6) {
        uint16_t rawV = parseUint16BE(data, 2);
        uint16_t rawI = parseUint16BE(data, 4);
        s.setVoltage = fromRaw(rawV, nomVoltage);
        s.setCurrent = fromRaw(rawI, nomCurrent);
    }
    return s;
}

// ── Value conversions ─────────────────────────────────────────────────────
double fromRaw(uint16_t raw, double nominal)
{
    return nominal * static_cast<double>(raw) / 25600.0;
}

uint16_t toRaw(double value, double nominal)
{
    if (nominal <= 0) return 0;
    double raw = 25600.0 * value / nominal;
    if (raw < 0) raw = 0;
    if (raw > 25600) raw = 25600;
    return static_cast<uint16_t>(std::round(raw));
}

double fromLimitRaw(uint16_t raw, double nominal)
{
    // OVP/OCP: nominal here is 1.1 * Unom
    return fromRaw(raw, nominal * 1.1);
}

uint16_t toLimitRaw(double value, double nominal)
{
    return toRaw(value, nominal * 1.1);
}

// ── Binary helpers ────────────────────────────────────────────────────────
float parseFloat32BE(const QByteArray& data, int offset)
{
    if (data.size() < offset + 4) return 0.0f;
    uint32_t bits = 0;
    bits |= static_cast<uint32_t>(static_cast<uint8_t>(data[offset]))     << 24;
    bits |= static_cast<uint32_t>(static_cast<uint8_t>(data[offset + 1])) << 16;
    bits |= static_cast<uint32_t>(static_cast<uint8_t>(data[offset + 2])) << 8;
    bits |= static_cast<uint32_t>(static_cast<uint8_t>(data[offset + 3]));
    float f;
    std::memcpy(&f, &bits, sizeof(f));
    return f;
}

uint16_t parseUint16BE(const QByteArray& data, int offset)
{
    if (data.size() < offset + 2) return 0;
    return static_cast<uint16_t>(
        (static_cast<uint8_t>(data[offset]) << 8) |
         static_cast<uint8_t>(data[offset + 1]));
}

} // namespace PS2000
