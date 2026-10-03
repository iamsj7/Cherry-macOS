#ifndef PROCESS_METRICS_H
#define PROCESS_METRICS_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>

bool ct_process_energy_nj(pid_t pid, uint64_t *nanojoules);
size_t ct_process_path(pid_t pid, char *buffer, size_t size);

#endif
