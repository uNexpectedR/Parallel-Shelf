// ── FileShare (exo-4d0, docs/design/room-swarm.md) ─────────────────────────────────
// The module seals, uploads, fetches and verifies; the backend only carries its answers.
// Each action re-reads the list so the view follows reduce(log).
void MusterUiBackend::loadFileShare()
{
    setFileShareJson(modules().muster_module.fileshare_files());
}

void MusterUiBackend::shareFile(const QString &path)
{
    setFileShareResultJson(modules().muster_module.fileshare_share(path));
    loadFileShare();
}

void MusterUiBackend::fetchFile(const QString &fileId, const QString &folder, const QString &privately)
{
    // An empty folder is the person's own Downloads, resolved here as the audit download does:
    // the module's process may not run with the person's HOME (inside Basecamp it need not).
    QString dir = folder.trimmed();
    if (dir.isEmpty()) dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (dir.isEmpty()) dir = QDir::homePath();
    QDir().mkpath(dir);
    const QString r = modules().muster_module.fileshare_fetch(fileId, dir, privately);
    // a call that raised answers nothing: say so, rather than show nothing at all
    setFileShareResultJson(r.isEmpty() ? QStringLiteral("{\"error\":\"the module did not answer\"}") : r);
    loadFileShare();
}

void MusterUiBackend::seedFile(const QString &fileId, const QString &on)
{
    setFileShareResultJson(modules().muster_module.fileshare_seed(fileId, on));
    loadFileShare();
}

void MusterUiBackend::retractFile(const QString &fileId)
{
