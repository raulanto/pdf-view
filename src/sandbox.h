#pragma once
#include <QStringList>
#include <QFile>

// fd 3 is an already opened regular PDF, inherited only by bwrap.
inline QStringList sandboxArguments(const QString &worker) {
    QStringList args = {"--unshare-all", "--unshare-user", "--unshare-net",
        "--disable-userns", "--die-with-parent", "--new-session", "--clearenv",
        "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib",
        "--symlink", "usr/lib", "/lib64", "--proc", "/proc", "--dev", "/dev",
        "--tmpfs", "/tmp", "--dir", "/app",
        "--ro-bind", worker, "/app/worker",
        "--ro-bind-fd", "3", "/document.pdf",
        "--setenv", "QT_QPA_PLATFORM", "offscreen",
        "--setenv", "HOME", "/nonexistent",
        "--setenv", "XDG_CACHE_HOME", "/tmp/cache",
        "--setenv", "LANG", "C.UTF-8", "--chdir", "/tmp"};
    if (QFile::exists("/etc/fonts")) args << "--ro-bind" << "/etc/fonts" << "/etc/fonts";
    args << "--" << "/app/worker";
    return args;
}
