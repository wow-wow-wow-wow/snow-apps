#include "snow_shot/runtime/memoryoptimizationcontroller.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QGuiApplication>
#include <QString>
#include <atomic>
#include <chrono>
#include <optional>

#include <malloc.h>
#include <sys/resource.h>
#include <unistd.h>

namespace snow_shot::runtime {
namespace {
// The kernel's PSI averages expose memory pressure since 4.20. When the
// interface is unavailable the controller treats the state as unknown instead
// of guessing.
std::optional<bool> memoryPressureElevated() {
    QFile pressure(QStringLiteral("/proc/pressure/memory"));
    if (!pressure.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return std::nullopt;
    }
    const QString some = QString::fromLatin1(pressure.readLine());
    const qsizetype start = some.indexOf(QStringLiteral("avg10="));
    if (start < 0) {
        return std::nullopt;
    }
    bool valid = false;
    const double avg10 = some.mid(start + 6).toDouble(&valid);
    if (!valid) {
        return std::nullopt;
    }
    return avg10 >= 5.0;
}

class LinuxMemoryBackend final {
  public:
    std::optional<bool> lowMemory() const {
        return memoryPressureElevated();
    }

    std::optional<ProcessMemorySample> sample() {
        // /proc/self/stat wraps the executable name in parentheses; everything
        // after the closing one has stable field positions.
        QFile stat(QStringLiteral("/proc/self/stat"));
        if (!stat.open(QIODevice::ReadOnly | QIODevice::Text)) {
            reportSampleError();
            return std::nullopt;
        }
        const QString content = QString::fromLatin1(stat.readAll());
        const qsizetype commandEnd = content.indexOf(QLatin1Char(')'));
        if (commandEnd < 0) {
            reportSampleError();
            return std::nullopt;
        }
        const QStringList fields =
            content.mid(commandEnd + 2).split(QLatin1Char(' '), Qt::SkipEmptyParts);
        // state is field 3 of stat, so minflt/majflt/rss map to 7/9/21 here.
        if (fields.size() <= 21) {
            reportSampleError();
            return std::nullopt;
        }
        bool minFaultsValid = false;
        bool majorFaultsValid = false;
        bool residentPagesValid = false;
        const std::uint64_t minorFaults = fields[7].toULongLong(&minFaultsValid);
        const std::uint64_t majorFaults = fields[9].toULongLong(&majorFaultsValid);
        const std::uint64_t residentPages = fields[21].toULongLong(&residentPagesValid);
        if (!minFaultsValid || !majorFaultsValid || !residentPagesValid) {
            reportSampleError();
            return std::nullopt;
        }
        const qint64 pageSize = sysconf(_SC_PAGESIZE);
        if (pageSize <= 0) {
            reportSampleError();
            return std::nullopt;
        }
        return ProcessMemorySample{residentPages * static_cast<std::uint64_t>(pageSize),
                                   minorFaults + majorFaults};
    }

  private:
    void reportSampleError() {
        const auto now = std::chrono::steady_clock::now();
        if (!m_lastError || now - *m_lastError >= std::chrono::minutes(5)) {
            m_lastError = now;
            qWarning() << "Memory sample unavailable: /proc/self/stat is not readable";
        }
    }

    std::optional<std::chrono::steady_clock::time_point> m_lastError;
};
} // namespace

MemoryOptimizationController::Options nativeMemoryOptimizationOptions() {
    MemoryOptimizationController::Options options;
    auto backend = std::make_shared<LinuxMemoryBackend>();
    options.lowMemory = [backend] { return backend->lowMemory(); };
    options.sample = [backend] { return backend->sample(); };
    options.trim = [] {
        // This releases unused allocator pages, preserving all live allocations.
        // malloc_trim reports whether pages were returned, not how many.
        return MemoryTrimResult{malloc_trim(0) != 0, 0, 0};
    };
    options.report = [](const MemoryTrimReport& report) {
        qInfo() << "Memory trim: pressure=" << report.lowMemory
                << "rss_before=" << report.before.memoryBytes << "rss_after="
                << (report.after ? QString::number(report.after->memoryBytes)
                                 : QStringLiteral("unavailable"))
                << "allocator_released_bytes=" << report.result.releasedBytes << "duration_ms="
                << std::chrono::duration<double, std::milli>(report.duration).count();
    };
    return options;
}

bool currentProcessOwnsForegroundWindow() {
    const auto* application = qobject_cast<QGuiApplication*>(QCoreApplication::instance());
    // Without GUI state, conservatively block automatic reclamation.
    return !application || QGuiApplication::applicationState() == Qt::ApplicationActive;
}
} // namespace snow_shot::runtime
