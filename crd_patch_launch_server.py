#!/usr/bin/env python3
target = '/opt/google/chrome-remote-desktop/chrome-remote-desktop'

with open(target, 'r') as f:
    content = f.read()

old = '''  def _launch_server(self, extra_x_args):
    x_auth_file = os.path.expanduser("~/.Xauthority")
    self.child_env["XAUTHORITY"] = x_auth_file
    display = self.get_unused_display_number()

    # Run "xauth add" with |child_env| so that it modifies the same XAUTHORITY
    # file which will be used for the X session.
    exit_code = subprocess.call("xauth add :%d . `mcookie`" % display,
                                env=self.child_env, shell=True)
    if exit_code != 0:
      raise Exception("xauth failed with code %d" % exit_code)

    # Disable the Composite extension iff the X session is the default
    # Unity-2D, since it uses Metacity which fails to generate DAMAGE
    # notifications correctly. See crbug.com/166468.
    x_session = choose_x_session()
    if (len(x_session) == 2 and
        x_session[1] == "/usr/bin/gnome-session --session=ubuntu-2d"):
      extra_x_args.extend(["-extension", "Composite"])

    self.child_env["DISPLAY"] = ":%d" % display

    if self.use_xvfb:
      self._launch_xvfb(display, x_auth_file, extra_x_args)
    else:
      self._launch_xorg(display, x_auth_file, extra_x_args)'''

new = '''  def _launch_server(self, extra_x_args):
    # SHARED SESSION PATCH: Use existing GDM X session instead of virtual one.
    self.child_env["DISPLAY"] = ":0"
    self.child_env["XAUTHORITY"] = "/run/user/1000/gdm/Xauthority"
    self.server_supports_randr = True
    # Dummy process so the monitor loop has a process to watch.
    self.server_proc = subprocess.Popen(["sleep", "infinity"],
                                        env=self.child_env)'''

if old in content:
    content = content.replace(old, new)
    with open(target, 'w') as f:
        f.write(content)
    print("OK: _launch_server patched")
else:
    print("ERROR: pattern not found - file may have changed")
