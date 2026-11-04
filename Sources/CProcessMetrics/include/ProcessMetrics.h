#ifndef PROCESS_METRICS_H
#define PROCESS_METRICS_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>

typedef struct {
    pid_t pid;
    uint16_t port;
    bool is_udp;
    char address[46]; // "*" means every interface.
} ct_socket;

typedef struct {
    pid_t parent_pid;
    uid_t uid;
    uint64_t start_seconds; // Unix time; 0 when unavailable.
    char name[64];
} ct_process_info;

typedef struct {
    uint64_t energy_nj;
    uint64_t footprint_bytes;
    uint64_t cpu_ns;
    uint64_t start_abstime;
} ct_process_usage;

/// Returns listening TCP sockets, plus bound UDP sockets when requested. Free the result with free().
/// Returns NULL only when the process list cannot be read.
ct_socket *ct_copy_sockets(bool include_udp, size_t *count);
bool ct_get_process_info(pid_t pid, ct_process_info *info);
bool ct_get_process_usage(pid_t pid, ct_process_usage *usage);
size_t ct_process_path(pid_t pid, char *buffer, size_t size);
size_t ct_process_directory(pid_t pid, char *buffer, size_t size);
/// Copies the process arguments, separated by spaces. Environment variables are never read.
size_t ct_process_arguments(pid_t pid, char *buffer, size_t size);

#endif
