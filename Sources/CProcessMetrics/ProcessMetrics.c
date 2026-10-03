#include "ProcessMetrics.h"
#include <libproc.h>
#include <sys/resource.h>

bool ct_process_energy_nj(pid_t pid, uint64_t *nanojoules) {
    struct rusage_info_v6 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&usage) != 0 || usage.ri_energy_nj == 0) {
        return false;
    }
    *nanojoules = usage.ri_energy_nj;
    return true;
}

size_t ct_process_path(pid_t pid, char *buffer, size_t size) {
    int length = proc_pidpath(pid, buffer, (uint32_t)size);
    return length > 0 ? (size_t)length : 0;
}
