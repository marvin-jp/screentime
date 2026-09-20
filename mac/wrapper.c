/* screentime launcher (macOS).
 *
 * Why this exists: Screen Recording / Accessibility permissions attach to a
 * process's code identity. A launchd job whose executable is a shell script
 * is attributed to /bin/bash — Apple's binary — so your grant never matches
 * and screencapture fails silently. This compiled binary is the app bundle's
 * main executable: it stays alive as the TCC "responsible process" and
 * spawns the capture loop as a child, which inherits the grants.
 *
 * The build passes the real script path at compile time, so the repo can live
 * anywhere. The default below only matches the documented clone location.
 *
 * Build:  cc -DSCRIPT_PATH='"/full/path/to/mac/capture-loop.sh"' \
 *            -o Screentime.app/Contents/MacOS/screentime mac/wrapper.c
 * Sign:   codesign -s - --force --identifier com.screentime Screentime.app
 * (Compile and sign ONCE, then grant permissions — re-signing invalidates
 *  existing grants.)
 */
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

int main(void) {
    char script[1024];
#ifdef SCRIPT_PATH
    snprintf(script, sizeof(script), "%s", SCRIPT_PATH);
#else
    snprintf(script, sizeof(script), "%s/screentime/mac/capture-loop.sh",
             getenv("HOME") ? getenv("HOME") : "");
#endif
    char *argv[] = {"/bin/bash", script, 0};
    for (;;) {
        pid_t pid;
        int status;
        if (posix_spawn(&pid, "/bin/bash", 0, 0, argv, environ) != 0)
            return 1;
        waitpid(pid, &status, 0);
        sleep(5); /* loop crashed or exited — restart it */
    }
}
