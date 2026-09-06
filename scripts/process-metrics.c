#include <errno.h>
#include <libproc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s pid\n", argv[0]);
        return 64;
    }

    char *end = NULL;
    errno = 0;
    long parsed_pid = strtol(argv[1], &end, 10);
    if (errno != 0 || end == argv[1] || *end != '\0' || parsed_pid <= 0 || parsed_pid > INT32_MAX) {
        fprintf(stderr, "invalid pid: %s\n", argv[1]);
        return 65;
    }

    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage((int)parsed_pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
        perror("proc_pid_rusage");
        return 66;
    }

    printf(
        "%llu %llu %llu %llu %llu %llu\n",
        usage.ri_user_time,
        usage.ri_system_time,
        usage.ri_resident_size,
        usage.ri_phys_footprint,
        usage.ri_pkg_idle_wkups,
        usage.ri_interrupt_wkups
    );
    return 0;
}
