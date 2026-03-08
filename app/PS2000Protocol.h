// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// PS2000Protocol.h — EA PS 2000 B binary telegram protocol helpers.
// Reference: ps2000b_programming.pdf, object_list_ps2000b_de_en.pdf
#pragma once

#include <QByteArray>
#include <QString>
#include <cstdint>

namespace PS2000 {

// ── Object IDs ─────────────────────────────────────────────────────────────
constexpr uint8_t OBJ_DEVICE_TYPE    =  0;   // ro string 16
constexpr uint8_t OBJ_SERIAL_NO      =  1;   // ro string 16
constexpr uint8_t OBJ_NOM_VOLTAGE    =  2;   // ro float  4
constexpr uint8_t OBJ_NOM_CURRENT    =  3;   // ro float  4
constexpr uint8_t OBJ_NOM_POWER      =  4;   // ro float  4
constexpr uint8_t OBJ_ARTICLE_NO     =  6;   // ro string 16
constexpr uint8_t OBJ_MANUFACTURER   =  8;   // ro string 16
constexpr uint8_t OBJ_SW_VERSION     =  9;   // ro string 16
constexpr uint8_t OBJ_DEVICE_CLASS   = 19;   // ro int    2
constexpr uint8_t OBJ_OVP            = 38;   // rw int    2  (% of 1.1*Unom*256)
constexpr uint8_t OBJ_OCP            = 39;   // rw int    2  (% of 1.1*Inom*256)
constexpr uint8_t OBJ_SET_VOLTAGE    = 50;   // rw int    2  (% of Unom*256)
constexpr uint8_t OBJ_SET_CURRENT    = 51;   // rw int    2  (% of Inom*256)
constexpr uint8_t OBJ_CONTROL        = 54;   // rw char   2  (mask + value)
constexpr uint8_t OBJ_STATUS_ACTUAL  = 71;   // ro int    6
constexpr uint8_t OBJ_STATUS_SET     = 72;   // ro int    6

// ── Telegram SD (start delimiter) constants ────────────────────────────────
// SD = type | cast | direction | (datalen-1)
constexpr uint8_t SD_SEND   = 0xC0;   // send data to device
constexpr uint8_t SD_QUERY  = 0x40;   // query device
constexpr uint8_t SD_ANSWER = 0x80;   // answer from device
constexpr uint8_t SD_CAST   = 0x20;   // broadcast (PC→device)
constexpr uint8_t SD_PC2DEV = 0x10;   // direction: PC to device

// ── Control byte values (object 54) ───────────────────────────────────────
// Sent as [mask, value] pair (2 bytes)
constexpr uint8_t CTRL_OUTPUT_MASK  = 0x01;
constexpr uint8_t CTRL_OUTPUT_ON    = 0x01;
constexpr uint8_t CTRL_OUTPUT_OFF   = 0x00;

constexpr uint8_t CTRL_ACK_MASK     = 0x0A;
constexpr uint8_t CTRL_ACK_ALARMS   = 0x0A;

constexpr uint8_t CTRL_REMOTE_MASK  = 0x10;
constexpr uint8_t CTRL_REMOTE_ON    = 0x10;
constexpr uint8_t CTRL_REMOTE_OFF   = 0x00;

// ── Status byte 0 bits (access mode) ──────────────────────────────────────
constexpr uint8_t SB0_REMOTE = 0x01;  // bit 0: 0=free, 1=remote

// ── Status byte 1 bits ────────────────────────────────────────────────────
constexpr uint8_t SB1_OUTPUT_ON = 0x01;  // bit 0
constexpr uint8_t SB1_CC        = 0x04;  // bits 2:1 = 10 → CC (constant current)
constexpr uint8_t SB1_REG_MASK  = 0x06;  // bits 2:1
constexpr uint8_t SB1_OVP       = 0x10;  // bit 4
constexpr uint8_t SB1_OCP       = 0x20;  // bit 5
constexpr uint8_t SB1_OPP       = 0x40;  // bit 6
constexpr uint8_t SB1_OTP       = 0x80;  // bit 7

// ── Parsed status structure ───────────────────────────────────────────────
struct DeviceStatus {
    bool    remoteMode  = false;
    bool    outputOn    = false;
    bool    ccMode      = false;   // false = CV
    bool    ovpActive   = false;
    bool    ocpActive   = false;
    bool    oppActive   = false;
    bool    otpActive   = false;
    double  voltage     = 0.0;    // actual V
    double  current     = 0.0;    // actual A
    double  power       = 0.0;    // computed W
    double  setVoltage  = 0.0;    // set point V (from obj 72)
    double  setCurrent  = 0.0;    // set point A (from obj 72)
};

// ── Device info structure ─────────────────────────────────────────────────
struct DeviceInfo {
    QString deviceType;
    QString serialNo;
    QString articleNo;
    QString manufacturer;
    QString swVersion;
    float   nomVoltage = 0.0f;
    float   nomCurrent = 0.0f;
    float   nomPower   = 0.0f;
    uint16_t deviceClass = 0;
    bool    isTriple   = false;  // device class 0x0018 = triple
};

// ── Telegram builders ─────────────────────────────────────────────────────

// Build query telegram: SD DN OBJ CS_HI CS_LO
// expectedDataLen = number of bytes expected in response data field
QByteArray buildQuery(uint8_t obj, uint8_t dn, int expectedDataLen);

// Build send telegram with raw data bytes: SD DN OBJ DATA... CS_HI CS_LO
QByteArray buildSend(uint8_t obj, uint8_t dn, const QByteArray& data);

// Build send for object 54 control (2 bytes: mask, value)
QByteArray buildControl(uint8_t dn, uint8_t mask, uint8_t value);

// Build send for a 16-bit setpoint (big-endian)
QByteArray buildSetInt(uint8_t obj, uint8_t dn, uint16_t rawValue);

// ── Response parser ───────────────────────────────────────────────────────

// Parse a complete response telegram.
// Returns true if valid (correct checksum, answer type SD).
// obj and data are output parameters.
bool parseResponse(const QByteArray& raw, uint8_t& obj, QByteArray& data);

// Parse device status from obj 71 data (6 bytes)
DeviceStatus parseStatus(const QByteArray& data, float nomVoltage, float nomCurrent);

// Parse device status + set values from obj 72 data (6 bytes)
DeviceStatus parseStatusSet(const QByteArray& data, float nomVoltage, float nomCurrent);

// ── Value conversions ─────────────────────────────────────────────────────

// Actual/setpoint values are percentage of nominal.  0x6400 = 25600 = 100%.
// actual_value = nominal * raw / 25600
// raw = 25600 * desired / nominal
double fromRaw(uint16_t raw, double nominal);
uint16_t toRaw(double value, double nominal);

// OVP/OCP thresholds: percentage of 1.1 * nominal * 256
// Note: 1.1 * Unom * 256 corresponds to 28160 for Unom where raw=28160 = 110%.
// Same formula applies: actual = 1.1*nominal * raw / 25600
double fromLimitRaw(uint16_t raw, double nominal);
uint16_t toLimitRaw(double value, double nominal);

// ── Binary helpers ────────────────────────────────────────────────────────
float    parseFloat32BE(const QByteArray& data, int offset = 0);
uint16_t parseUint16BE(const QByteArray& data, int offset = 0);
uint16_t checksum(const QByteArray& data);

// Expected total telegram length from response SD byte
int responseTotalLen(uint8_t sd);

} // namespace PS2000
