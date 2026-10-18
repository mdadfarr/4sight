// 4sight handlebar haptics. BLE spec: docs/CONTRACTS.md (frozen).
#include <Arduino.h>
#include <NimBLEDevice.h>

static const char* SERVICE_UUID = "5db17fa8-6860-4cd4-bd95-50e90510e072";
static const char* CMD_UUID     = "2490e4c3-b5b8-40db-8ab6-8cc856e1fa31";
static const char* EVT_UUID     = "0f343fab-5e83-41a9-afb1-07dc42818c5f";

enum Side { L = 0, R = 1 };
// Pin map (Hack the Valley build): one coin motor per grip through a 2N2222A (1k to the
// base, 1N4007 across the motor), a green and a red LED per side (150 ohm), a merge button
// per side to GND. Leave RX0, TX0, D2, D5, D12, D15, D21 free.
static const uint8_t MOTOR_PIN[2]    = {25, 26};
static const uint8_t BTN_PIN[2]      = {32, 33};        // merge buttons, to GND, INPUT_PULLUP
static const uint8_t MERGE_PIN[2][2] = {{18, 19}, {22, 23}};  // per side: {green, red}
static const uint8_t PWM_CH[2]       = {0, 1};
static const uint8_t DUTY_MAX = 255;  // full 3V3: at 80% the buzz was lost in road vibration (3 V motors, 10% over)

// Motor patterns: alternating on/off durations in ms, starting with ON.
struct Pattern { uint8_t n; uint16_t d[7]; };
static const Pattern PATTERNS[] = {
  {0, {}},                                    // 0: none
  {1, {300}},                                 // 1: one 300 ms pulse
  {3, {350, 150, 350}},                       // 2: two 350 ms pulses: long enough to feel through a moving bar
  {7, {250, 100, 250, 100, 250, 100, 250}},   // 3: 250 on / 100 off x4
  {1, {400}},                                 // 4: offline
};
static const uint8_t OFFLINE = 4;

// Per-side state
static uint8_t  level[2]   = {0, 0};   // 0..3, alert level; lights that side's red LED
static uint32_t lastCmd[2] = {0, 0};   // for 2 s LED timeout
static uint8_t  pending[2] = {0, 0};   // pattern waiting for the motor player

// Merge check, per side. Shares the red LED with alerts: either one lights it.
enum MergeState { M_IDLE = 0, M_WAIT, M_GREEN, M_RED, M_BLINK };
static uint8_t  mergeState[2] = {M_IDLE, M_IDLE};
static uint32_t mergeT0[2]    = {0, 0};
static uint8_t  btnStable[2]  = {HIGH, HIGH};
static uint8_t  btnLast[2]    = {HIGH, HIGH};
static uint32_t btnChange[2]  = {0, 0};
static NimBLECharacteristic* evtChr = nullptr;

// Single motor player: only one side's motors run at a time (3V3 budget).
static int8_t   active   = -1;
static uint8_t  activePat = 0;
static uint8_t  step     = 0;
static uint32_t stepStart = 0;

static volatile bool connected = false;
// Written by the BLE callbacks (other core), read by loop(): volatile so neither caches them.
static volatile uint32_t lastMsgMs = 0;
static volatile bool offlinePlayed = true;   // disarmed until the first command arrives

// BLE write lands here; loop() handles it so all state lives on one task.
static char     bleCmd[5] = {0};
static volatile bool bleCmdReady = false;

// Core 3 dropped ledcSetup/ledcAttachPin and ledcWrite takes the pin, not the channel.
static void pwmInit(int s) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(MOTOR_PIN[s], 200, 8);
#else
  ledcSetup(PWM_CH[s], 200, 8);
  ledcAttachPin(MOTOR_PIN[s], PWM_CH[s]);
#endif
}

static void pwmWrite(int s, uint8_t duty) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(MOTOR_PIN[s], duty);
#else
  ledcWrite(PWM_CH[s], duty);
#endif
}

static void motors(Side s, bool on) { pwmWrite(s, on ? DUTY_MAX : 0); }

static void stopPlayer() {
  if (active >= 0) motors((Side)active, false);
  active = -1;
}

static void startPlayer(Side s, uint32_t now) {
  stopPlayer();
  active = s; activePat = pending[s]; pending[s] = 0;
  step = 0; stepStart = now;
  motors(s, true);
}

static void allOff() {
  stopPlayer();
  for (int s = 0; s < 2; s++) { level[s] = 0; pending[s] = 0; }
}

static void handleCmd(const char* cmd, uint32_t now) {
  Serial.printf("cmd: %s\n", cmd);
  if (!strcmp(cmd, "H")) {
  } else if (!strcmp(cmd, "X")) {
    allOff();
  } else if ((cmd[0] == 'L' || cmd[0] == 'R') && cmd[1] >= '1' && cmd[1] <= '3' && cmd[2] == 0) {
    Side s = cmd[0] == 'L' ? L : R;
    level[s] = cmd[1] - '0';
    lastCmd[s] = now;
    pending[s] = level[s];
    if (active == s) stopPlayer();                    // restart this side's pattern
    else if (s == L && active == R) { pending[R] = activePat; stopPlayer(); }  // left wins, right re-queued
  } else if ((cmd[0] == 'G' || cmd[0] == 'N') && (cmd[1] == 'L' || cmd[1] == 'R') && cmd[2] == 0) {
    Side s = cmd[1] == 'L' ? L : R;          // merge answer: G = clear (green), N = blocked (red)
    // Only an answer to a press still waiting counts. Once the 1.5 s window has passed
    // the question is dead: the tracks behind a late answer are at least that old, which
    // is ~12 m of closing at city speed, so a late "clear" must not overwrite the red
    // blink. The rider presses again and gets a fresh answer.
    if (mergeState[s] == M_WAIT) {
      mergeState[s] = cmd[0] == 'G' ? M_GREEN : M_RED;
      mergeT0[s] = now;
      if (cmd[0] == 'N') pending[s] = 2;     // blocked: the grip says so too, two pulses
    } else {
      Serial.printf("late/unsolicited merge answer ignored: %s\n", cmd);
    }
  } else {
    Serial.printf("bad cmd: %s\n", cmd);
    return;
  }
  lastMsgMs = now;
  offlinePlayed = false;
}

class ServerCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    // Armed by the first command, not the connection: the phone needs ~1 s after
    // connecting to find the characteristic. Disarm before `connected` goes true, since
    // loop() on the other core can run between these lines.
    offlinePlayed = true; lastMsgMs = millis(); connected = true;
    Serial.println("ble: connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    connected = false; offlinePlayed = true;   // a clean disconnect is not a lost link
    Serial.println("ble: disconnected, advertising");
    NimBLEDevice::startAdvertising();
  }
};

class CmdCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
    std::string v = c->getValue();
    if (v.empty() || v.size() > 4 || bleCmdReady) return;  // shortcut: drops a write if loop() hasn't consumed the last one
    memcpy(bleCmd, v.data(), v.size()); bleCmd[v.size()] = 0;
    bleCmdReady = true;
  }
};

void setup() {
  Serial.begin(115200);
  for (int s = 0; s < 2; s++) {
    pinMode(BTN_PIN[s], INPUT_PULLUP);
    pinMode(MERGE_PIN[s][0], OUTPUT);
    pinMode(MERGE_PIN[s][1], OUTPUT);
    pwmInit(s);
    pwmWrite(s, 0);
  }

  NimBLEDevice::init("4sight");
  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCB());
  NimBLEService* svc = server->createService(SERVICE_UUID);
  NimBLECharacteristic* chr = svc->createCharacteristic(CMD_UUID, NIMBLE_PROPERTY::WRITE_NR);
  chr->setCallbacks(new CmdCB());
  evtChr = svc->createCharacteristic(EVT_UUID, NIMBLE_PROPERTY::NOTIFY);
  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setName("4sight");
  adv->start();
  Serial.println("4sight ready. Type L1..L3, R1..R3, X, H, GL/GR/NL/NR + Enter.");
}

void loop() {
  uint32_t now = millis();

  if (bleCmdReady) { handleCmd(bleCmd, now); bleCmdReady = false; }

  static char line[8]; static uint8_t len = 0;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (len) { line[len] = 0; handleCmd(line, now); }
      len = 0;
    } else if (len < sizeof(line) - 1) line[len++] = toupper(c);
    else len = 0;
  }

  if (connected && !offlinePlayed && now - lastMsgMs > 500) {
    Serial.println("offline");
    offlinePlayed = true;
    allOff();
    pending[L] = OFFLINE; pending[R] = OFFLINE;  // left then right, never both
  }

  // Motor player
  if (active >= 0) {
    const Pattern& p = PATTERNS[activePat];
    if (now - stepStart >= p.d[step]) {
      if (++step >= p.n) stopPlayer();
      else { stepStart = now; motors((Side)active, (step & 1) == 0); }
    }
  }
  if (active < 0) {
    if (pending[L]) startPlayer(L, now);
    else if (pending[R]) startPlayer(R, now);
  }

  // Alert levels time out 2 s after the last command; they light the red LED below.
  for (int s = 0; s < 2; s++) {
    if (level[s] && now - lastCmd[s] >= 2000) level[s] = 0;
  }

  // Merge buttons, debounced 25 ms. A press always restarts that side's cycle.
  for (int s = 0; s < 2; s++) {
    uint8_t r = digitalRead(BTN_PIN[s]);
    if (r != btnLast[s]) { btnLast[s] = r; btnChange[s] = now; }
    else if (r != btnStable[s] && now - btnChange[s] >= 25) {
      btnStable[s] = r;
      if (r == LOW) {
        mergeState[s] = M_WAIT; mergeT0[s] = now;
        if (evtChr) {
          evtChr->setValue((const uint8_t*)(s == L ? "ML" : "MR"), 2);
          evtChr->notify();
        }
        Serial.println(s == L ? "merge: ML" : "merge: MR");
      }
    }
  }

  // LEDs. Green only for a clear merge answer. Red for a blocked answer, for no answer
  // within 1.5 s (blinks 4 Hz for 3 s: unknown is never green), or for a car alert on
  // that side (steady; level 3 flashes 4 Hz). A car alert also cancels a green.
  for (int s = 0; s < 2; s++) {
    if (mergeState[s] == M_WAIT) {
      if (now - mergeT0[s] >= 1500) { mergeState[s] = M_BLINK; mergeT0[s] = now; }
    } else if (mergeState[s] != M_IDLE && now - mergeT0[s] >= 3000) {
      mergeState[s] = M_IDLE;
    }
    bool flash = (now / 125) & 1;
    bool alert = level[s] == 3 ? flash : level[s] > 0;
    bool red = alert || mergeState[s] == M_RED || (mergeState[s] == M_BLINK && flash);
    digitalWrite(MERGE_PIN[s][0], mergeState[s] == M_GREEN && level[s] == 0);
    digitalWrite(MERGE_PIN[s][1], red);
  }
}
