"""Shadows any installed e2b SDK (PYTHONPATH comes before site-packages) and
fails to import, to test cr-e2b on a machine without the SDK."""

raise ImportError("e2b is hidden for this test")
