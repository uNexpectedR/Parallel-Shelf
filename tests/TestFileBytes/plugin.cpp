#include "filebytes.h"

#include <QQmlEngine>
#include <QQmlExtensionPlugin>

// qmltestrunner only. Not packed in the lgx. Basecamp 0.3.2 QmlSandbox
// rejects a view qmldir that contains `plugin`.
class FileBytesPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterSingletonType<FileBytes>(uri, 1, 0, "TestFileBytes",
            [](QQmlEngine *, QJSEngine *) -> QObject * {
                return new FileBytes;
            });
    }
};

#include "plugin.moc"
