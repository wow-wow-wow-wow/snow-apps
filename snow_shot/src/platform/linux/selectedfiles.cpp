#include "snow_shot/platform/selectedfiles.h"

#include <functional>
#include <memory>
#include <utility>

namespace snow_shot::platform {
namespace {
// Wayland exposes no cross-process query for the foreground file manager's
// selection, so the capture-time "use selected files" flow reports an explicit
// unsupported signal instead of guessing a selection.
class UnsupportedSelectedFileBackend final : public SelectedFileBackend {
  public:
    [[nodiscard]] SelectedFileTarget captureTarget() const override {
        return {};
    }

    [[nodiscard]] bool isValidTarget(const SelectedFileTarget& target) const override {
        Q_UNUSED(target)
        return false;
    }

    [[nodiscard]] SelectedFileResult
    selectedFiles(const SelectedFileTarget& target,
                  const std::function<bool()>& cancelled) const override {
        Q_UNUSED(target)
        Q_UNUSED(cancelled)
        return {{}, SelectedFileError::Unavailable};
    }
};
} // namespace

std::shared_ptr<SelectedFileBackend> createSelectedFileBackend() {
    return std::make_shared<UnsupportedSelectedFileBackend>();
}
} // namespace snow_shot::platform
