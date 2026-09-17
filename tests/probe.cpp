#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <cstdio>
#include <cstring>
int main() {
    // This executable receives exactly the worker's sandbox policy.
    if (access("/home", F_OK) == 0 || access("/run/user", F_OK) == 0 || access("/etc/passwd", F_OK) == 0) return 1;
    int fd = open("/document.pdf", O_WRONLY);
    if (fd >= 0) { close(fd); return 2; }
    if (access("/document.pdf", R_OK) != 0) return 3;
    struct if_nameindex *interfaces = if_nameindex();
    if (!interfaces) return 4;
    for (auto p = interfaces; p->if_index; ++p) {
        if (strcmp(p->if_name, "lo") != 0) { if_freenameindex(interfaces); return 5; }
    }
    if_freenameindex(interfaces);
    int s = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    sockaddr_in dest{}; dest.sin_family = AF_INET; dest.sin_port = htons(80);
    inet_pton(AF_INET, "192.0.2.1", &dest.sin_addr);
    int result = connect(s, reinterpret_cast<sockaddr *>(&dest), sizeof(dest));
    close(s);
    if (result == 0) return 6;
    puts("isolated");
    return 0;
}
