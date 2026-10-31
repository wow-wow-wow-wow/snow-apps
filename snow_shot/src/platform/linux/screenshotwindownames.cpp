// SPDX-License-Identifier: GPL-3.0-only
#include "snow_shot/platform/screenshotwindownames.h"

namespace snow_shot::platform {
// Wayland clients cannot query other windows' titles at an arbitrary desktop
// point. Export naming falls back to its timestamp-based names; a
// foreign-toplevel backend can feed real names through this entry point later.
storage::ScreenshotWindowNames
screenshotWindowNamesAtPoint(const QPointF& point, std::span<const std::uintptr_t> excludedWindows,
                             storage::ScreenshotWindowNameFields fields) {
    Q_UNUSED(point)
    Q_UNUSED(excludedWindows)
    Q_UNUSED(fields)
    return {};
}
} // namespace snow_shot::platform
