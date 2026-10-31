#include "snow_shot/platform/linux/autostartregistration.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>

namespace snow_shot::platform::linux {
namespace {
QString autostartFilePath() {
    return QDir(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation))
        .filePath(QStringLiteral("autostart/snow_shot.desktop"));
}

QString desktopEntryContent() {
    const QString executable = QCoreApplication::applicationFilePath();
    return QStringLiteral(
               "[Desktop Entry]\n"
               "Type=Application\n"
               "Name=Snow Shot\n"
               "Comment=Screenshot utility for capturing, annotating, pinning, and recognizing "
               "screen content.\n"
               "Exec=\"%1\" --autostart\n"
               "Icon=snow-shot\n"
               "Terminal=false\n"
               "X-GNOME-Autostart-enabled=true\n")
        .arg(QString(executable).replace(QStringLiteral("\\"), QStringLiteral("\\\\"))
                 .replace(QStringLiteral("\""), QStringLiteral("\\\"")));
}
} // namespace

StartupRegistrationResult reconcileStartupMode(StartupMode mode) {
    const QString filePath = autostartFilePath();
    if (mode == StartupMode::Off) {
        if (QFile::exists(filePath) && !QFile::remove(filePath)) {
            return {false, QStringLiteral("Could not remove the XDG autostart entry: %1")
                               .arg(filePath)};
        }
        return {};
    }

    const QString content = desktopEntryContent();
    const QFileInfo info(filePath);
    if (!QDir().mkpath(info.absolutePath())) {
        return {false,
                QStringLiteral("Could not create the XDG autostart directory: %1")
                    .arg(info.absolutePath())};
    }
    QSaveFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text) ||
        file.write(content.toUtf8()) < 0 || !file.commit()) {
        return {false, QStringLiteral("Could not write the XDG autostart entry: %1").arg(filePath)};
    }
    return {};
}
} // namespace snow_shot::platform::linux
