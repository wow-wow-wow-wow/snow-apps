#include "snow_shot/platform/windowcaptureexclusion.h"

namespace snow_shot::platform {

// On Wayland the screen content reaches the application through the desktop
// portal, and a client cannot remove its own windows from the captured
// stream; both helpers degrade to the unsupported answers.
bool setWindowExcludedFromCapture(QWidget* /*window*/, bool /*excluded*/) {
    return false;
}

std::optional<std::uint32_t> captureWindowId(QWidget* /*window*/) {
    return std::nullopt;
}

} // namespace snow_shot::platform
