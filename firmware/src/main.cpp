// 4sight handlebar haptics. BLE spec: docs/CONTRACTS.md (frozen).
#include <Arduino.h>
#include <NimBLEDevice.h>

static const char* SERVICE_UUID = "5db17fa8-6860-4cd4-bd95-50e90510e072";
static const char* CMD_UUID     = "2490e4c3-b5b8-40db-8ab6-8cc856e1fa31";
static const char* EVT_UUID     = "0f343fab-5e83-41a9-afb1-07dc42818c5f";

enum Side { L = 0, R = 1 };
static const uint8_t MOTOR_PIN[2][2] = {{25, 26}, {32, 33}};
static const uint8_t LED_PIN[2]      = {27, 14};
static const uint8_t BTN_PIN[2]      = {18, 19};        // merge buttons, to GND, INPUT_PULLUP
static const uint8_t MERGE_PIN[2][2] = {{16, 17}, {22, 23}};  // per side: {green, red}
static const uint8_t PWM_CH[2][2]    = {{0, 1}, {2, 3}};
static const uint8_t DUTY_MAX = 204;  // 80% of 255, motor rating

// Motor patterns: alternating on/off durations in ms, starting with ON.
struct Pattern { uint8_t n; uint16_t d[7]; };
static const Pattern PATTERNS[] = {
  {0, {}},                                    // 0: none
  {1, {150}},                                 // 1: one 150 ms pulse
  {3, {120, 100, 120}},                       // 2: two 120 ms pulses, 100 ms apart
  {7, {100, 80, 100, 80, 100, 80, 100}},      // 3: 100 on / 80 off x4
  {1, {400}},                                 // 4: offline
};
static const uint8_t OFFLINE = 4;

// Per-side state
static uint8_t  level[2]   = {0, 0};   // 0..3, drives LED
static uint32_t lastCmd[2] = {0, 0};   // for 2 s LED timeout
static uint8_t  pending[2] = {0, 0};   // pattern waiting for the motor player

// Merge check, per side. Independent of the motor player and the amber LEDs.
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
static uint32_t lastMsgMs = 0;
static bool offlinePlayed = false;

// BLE write lands here; loop() handles it so all state lives on one task.
static char     bleCmd[5] = {0};
static volatile bool bleCmdReady = false;

static void motors(Side s, bool on) {
  ledcWrite(PWM_CH[s][0], on ? DUTY_MAX : 0);
  ledcWrite(PWM_CH[s][1], on ? DUTY_MAX : 0);
}

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
  for (int s = 0; s < 2; s++) { level[s] = 0; pending[s] = 0; digitalWrite(LED_PIN[s], LOW); }
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
    connected = true; lastMsgMs = millis(); offlinePlayed = false;
    Serial.println("ble: connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    connected = false;
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
    pinMode(LED_PIN[s], OUTPUT);
    pinMode(BTN_PIN[s], INPUT_PULLUP);
    pinMode(MERGE_PIN[s][0], OUTPUT);
    pinMode(MERGE_PIN[s][1], OUTPUT);
    for (int m = 0; m < 2; m++) {
      ledcSetup(PWM_CH[s][m], 200, 8);
      ledcAttachPin(MOTOR_PIN[s][m], PWM_CH[s][m]);
      ledcWrite(PWM_CH[s][m], 0);
    }
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

  // LEDs
  for (int s = 0; s < 2; s++) {
    if (level[s] && now - lastCmd[s] >= 2000) level[s] = 0;
    bool on = level[s] == 3 ? ((now / 125) & 1) : level[s] > 0;  // level 3: 4 Hz flash
    digitalWrite(LED_PIN[s], on);
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

  // Merge LEDs. Unknown is never green: no answer within 1.5 s blinks red 4 Hz for 3 s.
  for (int s = 0; s < 2; s++) {
    if (mergeState[s] == M_WAIT) {
      if (now - mergeT0[s] >= 1500) { mergeState[s] = M_BLINK; mergeT0[s] = now; }
    } else if (mergeState[s] != M_IDLE && now - mergeT0[s] >= 3000) {
      mergeState[s] = M_IDLE;
    }
    digitalWrite(MERGE_PIN[s][0], mergeState[s] == M_GREEN);
    digitalWrite(MERGE_PIN[s][1], mergeState[s] == M_RED ||
                                  (mergeState[s] == M_BLINK && ((now / 125) & 1)));
  }
}
