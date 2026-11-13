#pragma once

#include <string>

int StartLocalEngine(const std::string& script, const std::string& data);
int LocalEngineStatus();
void StopLocalEngine();
