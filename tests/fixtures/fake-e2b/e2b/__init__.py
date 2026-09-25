"""A stand-in for the e2b SDK, for tests. It records every call as one JSON
line in $FAKE_E2B_LOG and keeps the sandbox's files in $FAKE_E2B_FILES (a
directory), so a later process can connect to the "same" sandbox. A command
containing $FAKE_E2B_FAIL exits 1.

Only the surface cr-e2b uses: Sandbox.create, Sandbox.connect, sandbox_id,
commands.run, files.write, files.read, kill, and CommandExitException. The
signatures follow e2b 2.51.0.
"""

import json
import os


def _record(call, **kwargs):
    with open(os.environ["FAKE_E2B_LOG"], "a", encoding="utf-8") as f:
        f.write(json.dumps(dict(call=call, **kwargs)) + "\n")


class SandboxException(Exception):
    pass


class CommandExitException(SandboxException):
    def __init__(self, exit_code, stdout="", stderr=""):
        super().__init__("exit %d" % exit_code)
        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr


class CommandResult:
    def __init__(self, exit_code=0, stdout="", stderr=""):
        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr


class _Commands:
    def run(self, cmd, background=None, envs=None, user=None, cwd=None,
            on_stdout=None, on_stderr=None, stdin=None, timeout=60, request_timeout=None):
        _record("commands.run", cmd=cmd, cwd=cwd, timeout=timeout, background=background)
        fail = os.environ.get("FAKE_E2B_FAIL")
        if fail and fail in cmd:
            raise CommandExitException(1, stderr="fake failure of: " + cmd)
        return CommandResult()


class _Files:
    def _path(self, path):
        return os.path.join(os.environ["FAKE_E2B_FILES"], path.lstrip("/"))

    def write(self, path, data, user=None, request_timeout=None):
        _record("files.write", path=path, data=data)
        local = self._path(path)
        os.makedirs(os.path.dirname(local), exist_ok=True)
        with open(local, "w", encoding="utf-8") as f:
            f.write(data)

    def read(self, path, format="text", user=None, request_timeout=None):
        _record("files.read", path=path)
        with open(self._path(path), encoding="utf-8") as f:
            return f.read()


class Sandbox:
    def __init__(self, sandbox_id):
        self.sandbox_id = sandbox_id
        self.commands = _Commands()
        self.files = _Files()

    @classmethod
    def create(cls, template=None, timeout=None, metadata=None, envs=None, **opts):
        _record("Sandbox.create", template=template, timeout=timeout, metadata=metadata,
                envs=envs, api_key_set=bool(os.environ.get("E2B_API_KEY")))
        return cls("sbx-fake-1")

    @staticmethod
    def connect(sandbox_id, timeout=None, **opts):
        _record("Sandbox.connect", sandbox_id=sandbox_id)
        return Sandbox(sandbox_id)

    def kill(self, **opts):
        _record("kill", sandbox_id=self.sandbox_id)
        return True
