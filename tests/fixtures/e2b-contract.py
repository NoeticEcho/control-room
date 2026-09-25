"""Checks that the real e2b SDK has every call cr-e2b makes, with the
parameter names it passes: the contract the fake SDK in fake-e2b/ stands in
for. Run with the real SDK importable; exits 1 listing what is missing."""

import importlib.metadata
import inspect
import sys

import e2b
from e2b.sandbox_sync.commands.command import Commands
from e2b.sandbox_sync.filesystem.filesystem import Filesystem

USED = [
    ("Sandbox.create", e2b.Sandbox.create, ["template", "timeout", "metadata", "envs"]),
    ("Sandbox.connect (class form)", e2b.Sandbox._cls_connect_sandbox, ["sandbox_id"]),
    ("Sandbox.kill", e2b.Sandbox.kill, []),
    ("commands.run", Commands.run, ["cmd", "cwd", "timeout"]),
    ("files.write", Filesystem.write, ["path", "data"]),
    ("files.read", Filesystem.read, ["path"]),
]

missing = []
for name, function, params in USED:
    have = inspect.signature(function).parameters
    missing += ["%s(%s)" % (name, p) for p in params if p not in have]
for attr in ("exit_code", "stderr"):
    if attr not in getattr(e2b.CommandExitException, "__annotations__", {}) and not any(
            attr in getattr(base, "__annotations__", {}) for base in e2b.CommandExitException.__mro__):
        missing.append("CommandExitException.%s" % attr)
if not hasattr(e2b.Sandbox, "sandbox_id"):
    missing.append("Sandbox.sandbox_id")

if missing:
    print("the e2b SDK lacks: " + ", ".join(missing))
    sys.exit(1)
print("e2b %s has every call cr-e2b makes" % importlib.metadata.version("e2b"))
