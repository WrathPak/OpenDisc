#ifndef BLE_H
#define BLE_H

#include <Arduino.h>

void initBLE();
void bleTick();
void blePushState(const char* stateName);
void blePushThrowReady();
bool bleClientConnected();

// Debug log visible via web UI
#define DEBUG_LOG_SIZE 20
#define DEBUG_MSG_LEN  100
extern char debugLog[DEBUG_LOG_SIZE][DEBUG_MSG_LEN];
extern uint8_t debugLogHead;
extern uint8_t debugLogCount;
void debugMsg(const char* fmt, ...);

#endif
