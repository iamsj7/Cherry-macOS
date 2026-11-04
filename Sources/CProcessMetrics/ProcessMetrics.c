#include "ProcessMetrics.h"
#include <arpa/inet.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>

static void format_address(const struct in_sockinfo *info, char *buffer, size_t size) {
    if (info->insi_vflag & INI_IPV6) {
        const struct in6_addr *address = &info->insi_laddr.ina_6;
        if (IN6_IS_ADDR_UNSPECIFIED(address)) {
            strlcpy(buffer, "*", size);
        } else {
            inet_ntop(AF_INET6, address, buffer, (socklen_t)size);
        }
        return;
    }
    const struct in_addr *address = &info->insi_laddr.ina_46.i46a_addr4;
    if (address->s_addr == INADDR_ANY) {
        strlcpy(buffer, "*", size);
    } else {
        inet_ntop(AF_INET, address, buffer, (socklen_t)size);
    }
}

static bool append_socket(ct_socket **sockets, size_t *count, size_t *capacity, pid_t pid,
                          const struct in_sockinfo *info, bool is_udp) {
    uint16_t port = ntohs((uint16_t)info->insi_lport);
    if (port == 0) { return true; }
    if (*count == *capacity) {
        size_t next = *capacity == 0 ? 64 : *capacity * 2;
        ct_socket *grown = realloc(*sockets, next * sizeof(ct_socket));
        if (grown == NULL) { return false; }
        *sockets = grown;
        *capacity = next;
    }
    ct_socket *socket = &(*sockets)[(*count)++];
    memset(socket, 0, sizeof(*socket));
    socket->pid = pid;
    socket->port = port;
    socket->is_udp = is_udp;
    format_address(info, socket->address, sizeof(socket->address));
    return true;
}

static void collect_sockets(pid_t pid, bool include_udp, ct_socket **sockets, size_t *count, size_t *capacity) {
    int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (size <= 0) { return; } // Other users' and protected processes are not visible.
    int allocated = size + (int)(32 * sizeof(struct proc_fdinfo));
    struct proc_fdinfo *descriptors = malloc((size_t)allocated);
    if (descriptors == NULL) { return; }
    size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, descriptors, allocated);
    int total = size > 0 ? size / (int)sizeof(struct proc_fdinfo) : 0;
    for (int index = 0; index < total; index++) {
        if (descriptors[index].proc_fdtype != PROX_FDTYPE_SOCKET) { continue; }
        struct socket_fdinfo info;
        int read = proc_pidfdinfo(pid, descriptors[index].proc_fd, PROC_PIDFDSOCKETINFO, &info, sizeof(info));
        if (read < (int)sizeof(info)) { continue; }
        if (info.psi.soi_kind == SOCKINFO_TCP && info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN) {
            append_socket(sockets, count, capacity, pid, &info.psi.soi_proto.pri_tcp.tcpsi_ini, false);
        } else if (include_udp && info.psi.soi_kind == SOCKINFO_IN && info.psi.soi_protocol == IPPROTO_UDP) {
            append_socket(sockets, count, capacity, pid, &info.psi.soi_proto.pri_in, true);
        }
    }
    free(descriptors);
}

ct_socket *ct_copy_sockets(bool include_udp, size_t *count) {
    *count = 0;
    int estimate = proc_listallpids(NULL, 0);
    if (estimate <= 0) { return NULL; }
    int capacity_pids = estimate + 128;
    pid_t *pids = malloc((size_t)capacity_pids * sizeof(pid_t));
    if (pids == NULL) { return NULL; }
    int total = proc_listallpids(pids, capacity_pids * (int)sizeof(pid_t));
    if (total <= 0) {
        free(pids);
        return NULL;
    }
    ct_socket *sockets = NULL;
    size_t capacity = 0;
    for (int index = 0; index < total; index++) {
        collect_sockets(pids[index], include_udp, &sockets, count, &capacity);
    }
    free(pids);
    return sockets != NULL ? sockets : calloc(1, sizeof(ct_socket));
}

bool ct_get_process_info(pid_t pid, ct_process_info *info) {
    memset(info, 0, sizeof(*info));
    struct proc_bsdinfo full;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &full, sizeof(full)) == (int)sizeof(full)) {
        info->parent_pid = (pid_t)full.pbi_ppid;
        info->uid = full.pbi_uid;
        info->start_seconds = full.pbi_start_tvsec;
        strlcpy(info->name, full.pbi_name[0] != 0 ? full.pbi_name : full.pbi_comm, sizeof(info->name));
        return true;
    }
    struct proc_bsdshortinfo brief;
    if (proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 1, &brief, sizeof(brief)) == (int)sizeof(brief)) {
        info->parent_pid = (pid_t)brief.pbsi_ppid;
        info->uid = brief.pbsi_uid;
        strlcpy(info->name, brief.pbsi_comm, sizeof(info->name));
        return true;
    }
    return false;
}

bool ct_get_process_usage(pid_t pid, ct_process_usage *usage) {
    struct rusage_info_v6 raw = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&raw) != 0) { return false; }
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) { mach_timebase_info(&timebase); }
    usage->energy_nj = raw.ri_energy_nj;
    usage->footprint_bytes = raw.ri_phys_footprint;
    usage->cpu_ns = (raw.ri_user_time + raw.ri_system_time) * timebase.numer / timebase.denom;
    usage->start_abstime = raw.ri_proc_start_abstime;
    return true;
}

size_t ct_process_path(pid_t pid, char *buffer, size_t size) {
    int length = proc_pidpath(pid, buffer, (uint32_t)size);
    return length > 0 ? (size_t)length : 0;
}

size_t ct_process_directory(pid_t pid, char *buffer, size_t size) {
    struct proc_vnodepathinfo info;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, sizeof(info)) != (int)sizeof(info)) { return 0; }
    return strlcpy(buffer, info.pvi_cdir.vip_path, size);
}

size_t ct_process_arguments(pid_t pid, char *buffer, size_t size) {
    if (size == 0) { return 0; }
    buffer[0] = 0;
    int mib_max[2] = {CTL_KERN, KERN_ARGMAX};
    int max_size = 0;
    size_t length = sizeof(max_size);
    if (sysctl(mib_max, 2, &max_size, &length, NULL, 0) != 0 || max_size <= 0) { return 0; }
    char *raw = malloc((size_t)max_size);
    if (raw == NULL) { return 0; }
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t raw_size = (size_t)max_size;
    size_t written = 0;
    if (sysctl(mib, 3, raw, &raw_size, NULL, 0) == 0 && raw_size > sizeof(int)) {
        int argc = 0;
        memcpy(&argc, raw, sizeof(argc));
        char *cursor = raw + sizeof(int);
        char *end = raw + raw_size;
        while (cursor < end && *cursor != 0) { cursor++; } // Executable path.
        while (cursor < end && *cursor == 0) { cursor++; } // Padding.
        for (int index = 0; index < argc && cursor < end; index++) {
            size_t item = strnlen(cursor, (size_t)(end - cursor));
            if (written + item + 2 > size) { break; }
            if (written > 0) { buffer[written++] = ' '; }
            memcpy(buffer + written, cursor, item);
            written += item;
            buffer[written] = 0;
            cursor += item + 1;
        }
    }
    free(raw);
    return written;
}
