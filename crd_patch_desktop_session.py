#!/usr/bin/env python3
target = '/opt/google/chrome-remote-desktop/chrome-remote-desktop'

with open(target, 'r') as f:
    content = f.read()

old = '''  def launch_desktop_session(self):
    # Start desktop session.
    # The /dev/null input redirection is necessary to prevent the X session
    # reading from stdin.  If this code runs as a shell background job in a
    # terminal, any reading from stdin causes the job to be suspended.
    # Daemonization would solve this problem by separating the process from the
    # controlling terminal.
    xsession_command = choose_x_session()
    if xsession_command is None:
      raise Exception("Unable to choose suitable X session command.")

    logging.info("Launching X session: %s" % xsession_command)
    self.session_proc = subprocess.Popen(xsession_command,
                                         stdin=subprocess.DEVNULL,
                                         stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT,
                                         cwd=HOME_DIR,
                                         env=self.child_env)

    if not self.session_proc.pid:
      raise Exception("Could not start X session")

    output_filter_thread = SessionOutputFilterThread(self.session_proc.stdout,
        "Session output: ", SESSION_OUTPUT_TIME_LIMIT_SECONDS)
    output_filter_thread.start()


def parse_config_arg'''

new = '''  def launch_desktop_session(self):
    # SHARED SESSION PATCH: GDM session already running - start a dummy
    # process so the monitor loop has a session_proc to watch.
    logging.info("Shared session mode: attaching to existing GDM session.")
    self.session_proc = subprocess.Popen(["sleep", "infinity"],
                                         stdin=subprocess.DEVNULL,
                                         stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL,
                                         env=self.child_env)


def parse_config_arg'''

if old in content:
    content = content.replace(old, new)
    with open(target, 'w') as f:
        f.write(content)
    print("OK: launch_desktop_session patched")
else:
    print("ERROR: pattern not found - file may have changed")
