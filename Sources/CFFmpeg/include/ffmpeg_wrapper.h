#ifndef FFMPEG_WRAPPER_H
#define FFMPEG_WRAPPER_H

/**
 * Run an ffmpeg command with the given arguments (in-process, no subprocess).
 *
 * @param argc  Number of arguments (including argv[0] which should be "ffmpeg")
 * @param argv  Argument array (same format as CLI: "ffmpeg", "-i", "input.mxf", ...)
 * @param log_fd  File descriptor for stderr/stdout output:
 *                - >= 0: redirect output to this fd (for logging to file)
 *                - -1: capture output to internal buffer (retrieve with ffmpeg_get_captured_output)
 * @return ffmpeg exit code (0 = success, non-zero = error)
 */
int ffmpeg_run(int argc, char **argv, int log_fd);

/**
 * After calling ffmpeg_run with log_fd == -1, retrieve the captured stderr output.
 * The returned pointer is valid until the next ffmpeg_run call.
 */
const char *ffmpeg_get_captured_output(void);

#endif /* FFMPEG_WRAPPER_H */
