#ifndef SNOW_SHOT_PLATFORM_LINUX_AUTOSTARTREGISTRATION_H
#define SNOW_SHOT_PLATFORM_LINUX_AUTOSTARTREGISTRATION_H

#include <QString>

namespace snow_shot::platform::linux {

enum class StartupMode { Off, Standard, Elevated };

struct StartupRegistrationResult {
    bool success = true;
    QString error;
};

// Reconcile the XDG autostart entry with the requested mode. Elevated mirrors
// the Windows task-scheduler path but Linux autostart has no elevation, so it
// registers the same entry as Standard.
[[nodiscard]] StartupRegistrationResult reconcileStartupMode(StartupMode mode);

} // namespace snow_shot::platform::linux
#endif
