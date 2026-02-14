#include "ffmpeg_wrapper.h"
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>

/* Declared in patched fftools/ffmpeg.c */
extern int ffmpeg_main(int argc, char **argv);

static char *captured_buffer = NULL;
static size_t captured_size = 0;

int ffmpeg_run(int argc, char **argv, int log_fd) {
    int saved_stderr = dup(STDERR_FILENO);
    int saved_stdout = dup(STDOUT_FILENO);

    if (log_fd == -1) {
        /* Capture mode: redirect stderr to a pipe so we can read it back */
        int pipefd[2];
        if (pipe(pipefd) != 0) {
            close(saved_stderr);
            close(saved_stdout);
            return -1;
        }

        /* Make the read end non-blocking so we don't deadlock
           if ffmpeg fills the pipe buffer */
        fcntl(pipefd[0], F_SETFL, O_NONBLOCK);

        dup2(pipefd[1], STDERR_FILENO);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);

        /* Run ffmpeg */
        int ret = ffmpeg_main(argc, argv);

        /* Restore stderr/stdout before reading pipe */
        dup2(saved_stderr, STDERR_FILENO);
        dup2(saved_stdout, STDOUT_FILENO);
        close(saved_stderr);
        close(saved_stdout);

        /* Read captured output from pipe */
        free(captured_buffer);
        captured_buffer = NULL;
        captured_size = 0;

        char buf[4096];
        ssize_t n;
        while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) {
            char *new_buf = realloc(captured_buffer, captured_size + (size_t)n + 1);
            if (!new_buf) break;
            captured_buffer = new_buf;
            memcpy(captured_buffer + captured_size, buf, (size_t)n);
            captured_size += (size_t)n;
            captured_buffer[captured_size] = '\0';
        }
        close(pipefd[0]);

        return ret;
    } else {
        /* Log mode: redirect stderr+stdout to the provided file descriptor */
        dup2(log_fd, STDERR_FILENO);
        dup2(log_fd, STDOUT_FILENO);

        int ret = ffmpeg_main(argc, argv);

        /* Restore original stderr/stdout */
        dup2(saved_stderr, STDERR_FILENO);
        dup2(saved_stdout, STDOUT_FILENO);
        close(saved_stderr);
        close(saved_stdout);

        return ret;
    }
}

const char *ffmpeg_get_captured_output(void) {
    return captured_buffer ? captured_buffer : "";
}
