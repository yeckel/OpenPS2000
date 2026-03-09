# OpenPS2000 — Architecture

This document describes the software architecture of OpenPS2000 using UML diagrams.

---

## 1. High-Level Component Diagram

Shows how the main subsystems relate at startup (one backend is created, engines
are wired to it, QML accesses everything via context properties).

```mermaid
graph TB
    subgraph "Entry Point — main.cpp"
        MAIN["main()
        ─ parse CLI flags
        ─ auto-detect remote
        ─ create backend
        ─ create engines
        ─ wire signals/slots
        ─ load QML"]
    end

    subgraph "Backend  (exactly one)"
        LB["DeviceBackend
        ─ Q_PROPERTYs: voltage, current,
          power, setVoltage, setCurrent,
          outputOn, connected, …
        ─ Alarm detection
        ─ newSample() signal"]
        RB["RemoteBackend
        ─ Same Q_PROPERTYs & signals
        ─ Polls /api/v1/status @ 500 ms
        ─ Sends REST PUT commands"]
    end

    subgraph "Serial Layer  (local only)"
        ST["SerialTransport  [QThread]
        ─ 4 Hz GET_OBJECT poll
        ─ Coalescing command queue
        ─ enqueueUrgent() for E-Stop"]
        PROTO["PS2000Protocol
        ─ buildGetObject()
        ─ buildSetInt()
        ─ buildControl()
        ─ parseReply()
        ─ raw ↔ engineering value"]
    end

    subgraph "Engines"
        CE["ChargerEngine
        ─ States: Idle/CC/CV/Float/NegDV
        ─ 5 chemistries
        ─ Profile-driven"]
        PE["PulseEngine
        ─ States: Idle/OnPhase/OffPhase/Done
        ─ Software-timed square wave
        ─ Cycle counter"]
        SE["SequenceEngine
        ─ Multi-step V/I sequence
        ─ Ramp interpolation
        ─ Step/total progress"]
        SS["SequenceStore
        ─ Named profiles (JSON)
        ─ CSV/XLSX/ODS import/export"]
    end

    subgraph "Remote Services  (local only)"
        RS["RemoteServer  [QTcpServer]
        ─ HTTP/1.1 on port 8484
        ─ REST API endpoints
        ─ Bearer token auth
        ─ CORS headers"]
        MQ["MqttClient  [optional]
        ─ Publishes measurements
        ─ Subscribes to commands
        ─ #ifdef HAVE_QT_MQTT"]
    end

    subgraph "UI"
        TM["TrayManager
        ─ System tray icon
        ─ minimizeToTray setting"]
        QML["QML Engine
        ─ Main.qml
        ─ ChargerTab / PulseTab
        ─ SequenceTab
        ─ RemoteSettingsPanel
        ─ Canvas charts"]
    end

    MAIN -->|"creates"| LB
    MAIN -->|"creates (--remote)"| RB
    MAIN -->|"creates & wires"| CE & PE & SE & SS
    MAIN -->|"creates (local)"| RS & MQ & TM

    LB -->|"owns"| ST
    ST -->|"uses"| PROTO

    LB -->|"newSample(t,v,i,p)"| CE & PE & SE
    RB -->|"newSample(t,v,i,p)"| CE & PE & SE

    CE -->|"setVoltage/Current/Output"| LB
    CE -->|"setVoltage/Current/Output"| RB
    PE -->|"setVoltage/Current/Output"| LB
    PE -->|"setVoltage/Current/Output"| RB
    SE -->|"setVoltage/Current/Output"| LB
    SE -->|"setVoltage/Current/Output"| RB

    RS -->|"setpoint/output/limits"| LB
    MQ -->|"cmd signals"| LB
    LB -->|"newSample"| MQ

    QML -->|"context properties"| LB & RB & CE & PE & SE & SS & RS & MQ & TM

    style LB fill:#1a3a5c,stroke:#4a8fc0,color:#e0f0ff
    style RB fill:#1a3a5c,stroke:#4a8fc0,color:#e0f0ff
    style ST fill:#0d2a1a,stroke:#3a8f5a,color:#d0ffe0
    style PROTO fill:#0d2a1a,stroke:#3a8f5a,color:#d0ffe0
    style CE fill:#2a1a3a,stroke:#8f5ab0,color:#f0d0ff
    style PE fill:#2a1a3a,stroke:#8f5ab0,color:#f0d0ff
    style SE fill:#2a1a3a,stroke:#8f5ab0,color:#f0d0ff
    style SS fill:#2a1a3a,stroke:#8f5ab0,color:#f0d0ff
    style RS fill:#3a2a0d,stroke:#b08f3a,color:#fff0d0
    style MQ fill:#3a2a0d,stroke:#b08f3a,color:#fff0d0
    style QML fill:#1a1a3a,stroke:#5a5ab0,color:#d0d0ff
```

---

## 2. Class Diagram

Key classes with their most important members and relationships.

```mermaid
classDiagram
    direction LR

    class DeviceBackend {
        +Q_PROPERTY voltage
        +Q_PROPERTY current
        +Q_PROPERTY power
        +Q_PROPERTY setVoltage
        +Q_PROPERTY setCurrent
        +Q_PROPERTY outputOn
        +Q_PROPERTY connected
        +Q_PROPERTY nominalVoltage
        +Q_PROPERTY nominalCurrent
        +Q_PROPERTY remoteMode
        +connectDevice(port)
        +disconnectDevice()
        +sendSetVoltage(v)
        +sendSetCurrent(i)
        +setOutputOn(on)
        +setOutputOnQueued(on)
        +sendOvpVoltage(v)
        +sendOcpCurrent(i)
        +newSample(t,v,i,p) <<signal>>
        +connectedChanged() <<signal>>
        -m_transport: SerialTransport*
    }

    class RemoteBackend {
        +Q_PROPERTY voltage
        +Q_PROPERTY current
        +Q_PROPERTY power
        +Q_PROPERTY setVoltage
        +Q_PROPERTY setCurrent
        +Q_PROPERTY outputOn
        +Q_PROPERTY connected
        +sendSetVoltage(v)
        +sendSetCurrent(i)
        +setOutputOn(on)
        +setOutputOnQueued(on)
        +newSample(t,v,i,p) <<signal>>
        +connectedChanged() <<signal>>
        -m_startTime: double
        -m_pollTimer: QTimer
        -poll()
        -putJson(path, body)
    }

    class SerialTransport {
        +enqueueCommand(telegram)
        +enqueueUrgent(telegram)
        +dataReceived(data) <<signal>>
        -m_queue: QQueue
        -m_pollTimer: QTimer
        -run() [QThread]
    }

    class PS2000Protocol {
        +buildGetObject(obj)$ <<static>>
        +buildSetInt(obj, node, val)$ <<static>>
        +buildControl(node, mask, val)$ <<static>>
        +parseReply(data)$ <<static>>
        +toRaw(value, nominal)$ <<static>>
        +fromRaw(raw, nominal)$ <<static>>
    }

    class ChargerEngine {
        +Q_PROPERTY state
        +Q_PROPERTY stateString
        +Q_PROPERTY mAhCharged
        +Q_PROPERTY whCharged
        +Q_PROPERTY elapsedSecs
        +startCharging(profile)
        +stopCharging()
        +onSample(t,v,i,p)
        +setVoltageRequested(v) <<signal>>
        +setCurrentRequested(i) <<signal>>
        +setOutputRequested(on) <<signal>>
        -m_state: State
        -m_tickTimer: QTimer
    }

    class PulseEngine {
        +Q_PROPERTY state
        +Q_PROPERTY cyclesDone
        +Q_PROPERTY elapsedSecs
        +Q_PROPERTY actualVoltage
        +Q_PROPERTY actualCurrent
        +start(onV,onI,offV,offI,…)
        +stop()
        +onSample(t,v,i,p)
        +setVoltageRequested(v) <<signal>>
        +setCurrentRequested(i) <<signal>>
        +setOutputQueuedRequested(on) <<signal>>
        +setOutputRequested(on) <<signal>>
        -m_phaseTimer: QTimer
        -m_tickTimer: QTimer
        -applyOn()
        -applyOff()
    }

    class SequenceEngine {
        +Q_PROPERTY state
        +Q_PROPERTY stepProgress
        +Q_PROPERTY totalProgress
        +Q_PROPERTY phaseName
        +Q_PROPERTY totalSteps
        +start(profile)
        +stop()
        +onSample(t,v,i,p)
        +setVoltageRequested(v) <<signal>>
        +setCurrentRequested(i) <<signal>>
        +setOutputRequested(on) <<signal>>
        -m_steps: QList~SequenceStep~
        -m_stepTimer: QTimer
    }

    class RemoteServer {
        +start(port, token)
        +stop()
        +isRunning() bool
        +setpointReceived(v,i) <<signal>>
        +outputReceived(on) <<signal>>
        +limitsReceived(ovp,ocp) <<signal>>
        -m_server: QTcpServer
        -handleRequest(conn, req)
        -routeGet(path)
        -routePut(path, body)
    }

    class MqttClient {
        +connectToHost(host,port,…)
        +disconnect()
        +Q_PROPERTY connected
        +cmdSetpoint(v,i) <<signal>>
        +cmdOutput(on) <<signal>>
        +cmdLimits(ovp,ocp) <<signal>>
        -m_client: QMqttClient
        -publishMeasurement(v,i,p,t)
    }

    class TrayManager {
        +setWindow(window)
        +hideToTray()
        +showWindow()
        +Q_PROPERTY minimizeToTray
        +showRequested() <<signal>>
        -m_trayIcon: QSystemTrayIcon
    }

    class SequenceStore {
        +names() QStringList
        +save(name, profile)
        +load(name) SequenceProfile
        +remove(name)
        -m_profiles: QMap
    }

    DeviceBackend *-- SerialTransport : owns
    SerialTransport ..> PS2000Protocol : uses
    ChargerEngine ..> DeviceBackend : signals→slots
    ChargerEngine ..> RemoteBackend : signals→slots
    PulseEngine ..> DeviceBackend : signals→slots
    PulseEngine ..> RemoteBackend : signals→slots
    SequenceEngine ..> DeviceBackend : signals→slots
    SequenceEngine ..> RemoteBackend : signals→slots
    DeviceBackend ..> ChargerEngine : newSample
    DeviceBackend ..> PulseEngine : newSample
    DeviceBackend ..> SequenceEngine : newSample
    RemoteBackend ..> ChargerEngine : newSample
    RemoteBackend ..> PulseEngine : newSample
    RemoteBackend ..> SequenceEngine : newSample
    RemoteServer ..> DeviceBackend : commands
    MqttClient ..> DeviceBackend : commands
    DeviceBackend ..> MqttClient : newSample
    SequenceEngine --> SequenceStore : reads profiles
```

---

## 3. Sequence Diagram — Local Mode Measurement Cycle

How a single measurement round-trip works at 4 Hz.

```mermaid
sequenceDiagram
    participant Timer as QTimer (4 Hz)
    participant ST as SerialTransport
    participant PSU as EA-PS 2084-05 B
    participant PROTO as PS2000Protocol
    participant DB as DeviceBackend
    participant QML as QML / UI

    Timer->>ST: timeout()
    ST->>PROTO: buildGetObject(OBJ_MEAS_VOLTAGE)
    PROTO-->>ST: telegram bytes
    ST->>PSU: write(telegram)
    PSU-->>ST: reply bytes
    ST->>PROTO: parseReply(bytes)
    PROTO-->>ST: voltage value
    ST->>PROTO: buildGetObject(OBJ_MEAS_CURRENT)
    PROTO-->>ST: telegram bytes
    ST->>PSU: write(telegram)
    PSU-->>ST: reply bytes
    ST->>PROTO: parseReply(bytes)
    PROTO-->>ST: current value
    ST->>DB: measurementReceived(v, i)
    DB->>DB: compute power, integrate energy
    DB->>QML: newSample(t, v, i, p)  [signal]
    QML->>QML: update labels, chart
```

---

## 4. Sequence Diagram — Remote Mode Poll Cycle

How the remote client keeps its UI in sync with the server.

```mermaid
sequenceDiagram
    participant Timer as QTimer (500 ms)
    participant RB as RemoteBackend
    participant NET as QNetworkAccessManager
    participant SRV as RemoteServer (server process)
    participant DB as DeviceBackend (server)
    participant QML as QML / UI (client)

    Timer->>RB: timeout() → poll()
    RB->>NET: GET /api/v1/status
    NET->>SRV: HTTP request
    SRV->>DB: read properties
    DB-->>SRV: v, i, p, outputOn, setpoints
    SRV-->>NET: 200 OK  {"v":12.3,"i":0.5,…}
    NET-->>RB: QNetworkReply
    RB->>RB: parse JSON, emit newSample(t,v,i,p)
    RB->>QML: property updates + newSample signal
    QML->>QML: update labels, chart
```

---

## 5. Sequence Diagram — Pulse Cycle (one ON/OFF period)

How `PulseEngine` drives the PSU through one pulse period.

```mermaid
sequenceDiagram
    participant QML as PulseTab.qml
    participant PE as PulseEngine
    participant BE as Backend (local or remote)
    participant PSU as EA-PS 2084-05 B

    QML->>PE: start(onV, onI, offV, offI, onMs, offMs, cycles)
    PE->>BE: setVoltageRequested(onV)
    PE->>BE: setCurrentRequested(onI)
    PE->>BE: setOutputQueuedRequested(true)
    BE->>PSU: SET_VOLTAGE(onV)
    BE->>PSU: SET_CURRENT(onI)
    BE->>PSU: CTRL_OUTPUT_ON
    note over PE: phaseTimer started (onMs)

    PE->>PE: phaseTimer timeout → OnPhase ended
    PE->>BE: setVoltageRequested(offV)
    PE->>BE: setCurrentRequested(offI)
    PE->>BE: setOutputQueuedRequested(true/false)
    BE->>PSU: SET_VOLTAGE(offV)
    BE->>PSU: SET_CURRENT(offI)
    note over PE: phaseTimer started (offMs)

    PE->>PE: phaseTimer timeout → OffPhase ended
    PE->>PE: cyclesDone++
    alt more cycles remaining
        PE->>BE: applyOn() → next cycle
    else all done
        PE->>BE: setOutputRequested(false)
        PE->>QML: finished(cyclesDone) [signal]
    end
```

---

## 6. State Machines

### PulseEngine states
```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> OnPhase : start()
    OnPhase --> OffPhase : phaseTimer (onMs)
    OffPhase --> OnPhase : phaseTimer (offMs)\n[more cycles]
    OffPhase --> Done : phaseTimer (offMs)\n[all cycles done]
    OnPhase --> Idle : stop()
    OffPhase --> Idle : stop()
    Done --> Idle : start() again
```

### ChargerEngine states
```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> CC : startCharging()
    CC --> CV : voltage reached target
    CV --> Float : current < terminationI\n[Pb only]
    CV --> Idle : current < terminationI\n[Li-ion / LiFe]
    CC --> NegDV : −ΔV detected\n[NiCd / NiMH]
    CC --> Idle : timeout / fault
    CV --> Idle : timeout / fault
    Float --> Idle : stop() / fault
    NegDV --> Idle : always (done)
```
