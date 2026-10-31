#include "../../presentation/services/globalshortcutbackend_p.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QKeySequence>
#include <QObject>
#include <QTimer>

#include <QHash>
#include <QList>
#include <memory>

namespace snow_shot::presentation {
namespace {

const QString kPortalService = QStringLiteral("org.freedesktop.portal.Desktop");
const QString kPortalPath = QStringLiteral("/org/freedesktop/portal/desktop");
const QString kPortalInterface = QStringLiteral("org.freedesktop.portal.GlobalShortcuts");
const QString kRequestInterface = QStringLiteral("org.freedesktop.portal.Request");
const QString kSessionInterface = QStringLiteral("org.freedesktop.portal.Session");

// The GlobalShortcuts portal (version 2) describes every shortcut as
// (id, properties) with "description" and "preferred_binding" string keys.
using PortalShortcut = QPair<QString, QVariantMap>;

} // namespace

// External linkage: the QDBusArgument marshallers are found by ADL when the
// metatypes below are registered, and anonymous-namespace functions would be
// flagged as unused.
QDBusArgument& operator<<(QDBusArgument& argument, const PortalShortcut& shortcut) {
    argument.beginStructure();
    argument << shortcut.first << shortcut.second;
    argument.endStructure();
    return argument;
}

const QDBusArgument& operator>>(const QDBusArgument& argument, PortalShortcut& shortcut) {
    argument.beginStructure();
    argument >> shortcut.first >> shortcut.second;
    argument.endStructure();
    return argument;
}

namespace {

class PortalGlobalShortcutBackend final : public QObject, public GlobalShortcutBackend {
  public:
    explicit PortalGlobalShortcutBackend(QObject* parent = nullptr) : QObject(parent) {
        qDBusRegisterMetaType<PortalShortcut>();
        qDBusRegisterMetaType<QList<PortalShortcut>>();
        rebindTimer_.setSingleShot(true);
        connect(&rebindTimer_, &QTimer::timeout, this,
                &PortalGlobalShortcutBackend::bindShortcuts);
    }

    ~PortalGlobalShortcutBackend() override { teardownSession(); }

    void setActivationHandler(ActivationHandler handler) override {
        activationHandler_ = std::move(handler);
    }

    void setAvailabilityChangedHandler(AvailabilityChangedHandler handler) override {
        availabilityChanged_ = std::move(handler);
    }

    GlobalShortcutValidationResult
    validateShortcut(const shortcuts::ShortcutBinding& binding) const override {
        const QKeySequence sequence(binding.portableText, QKeySequence::PortableText);
        const bool valid = binding.portableText.isEmpty() || sequence.count() > 0;
        GlobalShortcutValidationResult result;
        result.binding = binding;
        result.shortcut = binding.portableText;
        result.supported = valid;
        result.failureReason = valid ? GlobalShortcutFailureReason::None
                                     : GlobalShortcutFailureReason::InvalidShortcut;
        return result;
    }

    // The portal binds asynchronously: the desktop environment shows a one-time
    // dialog for the requested keys. Optimistic success keeps the manager's
    // state machine simple; a rejected or failed bind invalidates the queued
    // registrations through availabilityChanged, which drives reconcile().
    GlobalShortcutBackendResult registerShortcut(int registrationId,
                                                 const shortcuts::ShortcutBinding& binding) override {
        if (binding.portableText.isEmpty() ||
            QKeySequence(binding.portableText, QKeySequence::PortableText).count() == 0) {
            return {false, GlobalShortcutFailureReason::InvalidShortcut, 0};
        }
        pending_.insert(registrationId,
                        qMakePair(portalIdFor(registrationId), binding.portableText));
        scheduleBind();
        return {true, GlobalShortcutFailureReason::None, 0};
    }

    void unregisterShortcut(int registrationId) override {
        pending_.remove(registrationId);
        bound_.remove(registrationId);
    }

  private:
    enum class Phase { Idle, Creating, Ready };

    static QString portalIdFor(int registrationId) {
        return QStringLiteral("snow-shot-%1").arg(registrationId);
    }

    static QString newToken() {
        static int counter = 0;
        return QStringLiteral("snow_shot_token_%1").arg(++counter);
    }

    void scheduleBind() {
        switch (phase_) {
        case Phase::Idle:
            createSession();
            break;
        case Phase::Ready:
            if (binding_) {
                rebindRequested_ = true;
            } else {
                bindShortcuts();
            }
            break;
        case Phase::Creating:
            bindQueued_ = true;
            break;
        }
    }

    void createSession() {
        phase_ = Phase::Creating;
        const QString token = newToken();
        watchRequest(token);

        QVariantMap options;
        options.insert(QStringLiteral("handle_token"), token);
        options.insert(QStringLiteral("session_handle_token"), QStringLiteral("snow_shot"));
        options.insert(QStringLiteral("version"), 2u);

        QDBusMessage message = QDBusMessage::createMethodCall(
            kPortalService, kPortalPath,
            kPortalInterface, QStringLiteral("CreateSession"));
        message << options;
        auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message),
                                                    this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                &PortalGlobalShortcutBackend::createSessionFinished);
    }

    void createSessionFinished(QDBusPendingCallWatcher* watcher) {
        watcher->deleteLater();
        if (phase_ != Phase::Creating) {
            return;
        }
        const QDBusPendingReply<QDBusObjectPath> reply = *watcher;
        if (reply.isError()) {
            invalidateAll();
            return;
        }
        sessionPath_ = reply.value().path();
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.connect(kPortalService, sessionPath_, kSessionInterface,
                    QStringLiteral("Closed"), this, SLOT(sessionClosed()));
        bus.connect(kPortalService, sessionPath_, kPortalInterface,
                    QStringLiteral("Activated"), this,
                    SLOT(shortcutActivated(QDBusMessage)));
        phase_ = Phase::Ready;
        if (bindQueued_ || !pending_.isEmpty()) {
            bindQueued_ = false;
            bindShortcuts();
        }
    }

    // Portal requests answer through a Response signal on a predictable object
    // path derived from the unique bus name and the handle_token option.
    void watchRequest(const QString& token) {
        QString sender = QDBusConnection::sessionBus().baseService();
        if (sender.startsWith(QLatin1Char(':'))) {
            sender.remove(0, 1);
        }
        sender.replace(QLatin1Char('.'), QLatin1Char('_'));
        responsePath_ = QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2")
                            .arg(sender, token);
        QDBusConnection::sessionBus().connect(kPortalService, responsePath_, kRequestInterface,
                                              QStringLiteral("Response"), this,
                                              SLOT(portalResponse(QDBusMessage)));
    }

    void bindShortcuts() {
        if (phase_ != Phase::Ready || sessionPath_.isEmpty()) {
            return;
        }
        if (pending_.isEmpty() || binding_) {
            rebindRequested_ = rebindRequested_ || binding_;
            return;
        }
        binding_ = true;
        const QString token = newToken();
        watchRequest(token);

        QList<PortalShortcut> shortcuts;
        for (auto it = pending_.cbegin(); it != pending_.cend(); ++it) {
            QVariantMap properties;
            properties.insert(QStringLiteral("description"), it.value().second);
            properties.insert(QStringLiteral("preferred_binding"), it.value().second);
            shortcuts.append(qMakePair(it.value().first, properties));
        }

        QVariantMap options;
        options.insert(QStringLiteral("handle_token"), token);

        QDBusMessage message = QDBusMessage::createMethodCall(
            kPortalService, kPortalPath,
            kPortalInterface, QStringLiteral("BindShortcuts"));
        message << QVariant::fromValue(QDBusObjectPath(sessionPath_))
                << QVariant::fromValue(shortcuts) << QString() << options;
        auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message),
                                                    this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](auto* call) {
            auto* pending = static_cast<QDBusPendingCallWatcher*>(call);
            pending->deleteLater();
            binding_ = false;
            const QDBusPendingReply<QDBusObjectPath> reply = *pending;
            if (reply.isError()) {
                scheduleRebind();
            }
            // The Response signal decides success; call errors are retried once.
        });
    }

    void portalResponse(QDBusMessage message) {
        if (message.arguments().isEmpty()) {
            return;
        }
        const quint32 response = message.arguments().first().toUInt();
        if (response != 0) {
            // 1 = the user dismissed the dialog, 2 = other error.
            invalidateAll();
            return;
        }
        if (phase_ != Phase::Ready) {
            // CreateSession completion is owned by the call watcher.
            return;
        }
        for (auto it = pending_.cbegin(); it != pending_.cend(); ++it) {
            bound_.insert(it.key(), it.value());
        }
        pending_.clear();
        if (rebindRequested_) {
            rebindRequested_ = false;
            bindShortcuts();
        }
    }

    void invalidateAll() {
        const QList<int> invalidated = pending_.keys() + bound_.keys();
        pending_.clear();
        bound_.clear();
        teardownSession();
        if (!invalidated.isEmpty() && availabilityChanged_ != nullptr) {
            availabilityChanged_(invalidated);
        }
    }

    void scheduleRebind() {
        if (!rebindTimer_.isActive()) {
            rebindTimer_.start(500);
        }
    }

    void teardownSession() {
        if (!responsePath_.isEmpty()) {
            QDBusConnection::sessionBus().disconnect(kPortalService, responsePath_,
                                                     kRequestInterface, QStringLiteral("Response"),
                                                     this,
                                                     SLOT(portalResponse(QDBusMessage)));
            responsePath_.clear();
        }
        if (!sessionPath_.isEmpty()) {
            QDBusConnection bus = QDBusConnection::sessionBus();
            bus.disconnect(kPortalService, sessionPath_, kSessionInterface,
                           QStringLiteral("Closed"), this, SLOT(sessionClosed()));
            bus.disconnect(kPortalService, sessionPath_, kPortalInterface,
                           QStringLiteral("Activated"), this,
                           SLOT(shortcutActivated(QDBusMessage)));
            sessionPath_.clear();
        }
        phase_ = Phase::Idle;
    }

  private Q_SLOTS:
    void sessionClosed() { invalidateAll(); }

    void shortcutActivated(const QDBusMessage& message) {
        if (activationHandler_ == nullptr || message.arguments().size() < 2) {
            return;
        }
        const QString portalId = message.arguments().at(1).toString();
        for (auto it = bound_.cbegin(); it != bound_.cend(); ++it) {
            if (it.value().first == portalId) {
                activationHandler_(it.key());
                return;
            }
        }
    }

  private:
    ActivationHandler activationHandler_;
    AvailabilityChangedHandler availabilityChanged_;
    QHash<int, QPair<QString, QString>> pending_; // registrationId -> (portalId, keys)
    QHash<int, QPair<QString, QString>> bound_;
    QString sessionPath_;
    QString responsePath_;
    Phase phase_ = Phase::Idle;
    bool binding_ = false;
    bool bindQueued_ = false;
    bool rebindRequested_ = false;
    QTimer rebindTimer_{this};
};

} // namespace

std::unique_ptr<GlobalShortcutBackend> createPortalGlobalShortcutBackend() {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() ||
        !bus.interface()->isServiceRegistered(kPortalService)) {
        return nullptr;
    }
    return std::make_unique<PortalGlobalShortcutBackend>();
}

} // namespace snow_shot::presentation
