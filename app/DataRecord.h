// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// DataRecord.h — One recorded measurement sample.
#pragma once

#include <cstdint>

struct DataRecord {
    double  timestamp  = 0.0;   // seconds since session start
    double  voltage    = 0.0;   // actual voltage (V)
    double  current    = 0.0;   // actual current (A)
    double  power      = 0.0;   // actual power (W)
    double  setVoltage = 0.0;   // setpoint voltage (V)
    double  setCurrent = 0.0;   // setpoint current (A)
    bool    outputOn   = false;
    bool    ccMode     = false;  // true = CC, false = CV
    bool    remoteMode = false;
    double  energyCum  = 0.0;   // cumulative energy (Wh)
};
