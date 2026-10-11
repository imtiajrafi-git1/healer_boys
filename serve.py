#!/usr/bin/env python3
# ============================================================================
# serve.py — Healer Boy's local preview server
# ----------------------------------------------------------------------------
# Why not `python3 -m http.server`?  Because it lets browsers cache index.html
# and the CSS files, so edits look like they "did not apply". This server is
# the same static file server with three preview-friendly extras:
#
#   1. every response carries `Cache-Control: no-store` → a refresh always
#      shows the current build (no stale CSS/JS while iterating)
#   2. `/demo` is a real route: it redirects to the one-click demo register
#      (demo data + demo admin, nothing is written to Supabase)
#   3. request logging includes the Host header, so it is visible when the
#      sandbox preview proxy (or your phone) is the one being served
#
# Usage:
#     python3 serve.py                 # 0.0.0.0:8080, this directory
#     python3 serve.py --port 5000     # another port
#     python3 serve.py --no-cache off  # honour normal HTTP caching
# ============================================================================

import argparse
import functools
import http.server
import socketserver
import sys

DEFAULT_PORT = 8080
DEMO_LOCATION = "/?demo=1#/demo"


class PreviewHandler(http.server.SimpleHTTPRequestHandler):
    """Static files, optionally no-store, plus a /demo shortcut."""

    no_store = True

    # ---- /demo → one-click demo register ------------------------------------
    def do_GET(self):
        if self.path.split("?")[0].rstrip("/") == "/demo":
            self.send_response(302)
            self.send_header("Location", DEMO_LOCATION)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.log_message("demo shortcut -> %s", DEMO_LOCATION)
            return
        return super().do_GET()

    def do_HEAD(self):
        if self.path.split("?")[0].rstrip("/") == "/demo":
            self.send_response(302)
            self.send_header("Location", DEMO_LOCATION)
            self.end_headers()
            return
        return super().do_HEAD()

    # ---- headers: never let a preview go stale ------------------------------
    def end_headers(self):
        if self.no_store:
            self.send_header("Cache-Control", "no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
        # the app is served inside the sandbox preview iframe: send no
        # X-Frame-Options at all (any value here would only risk blocking it)
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    # ---- logging: show which host is being served ---------------------------
    def log_message(self, fmt, *args):
        try:
            host = self.headers.get("Host", "-")
        except Exception:
            host = "-"
        sys.stderr.write("[%s] %s %s\n" % (host, self.address_string(), fmt % args))


class ThreadingServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser(description="Healer Boy's preview server")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--directory", default=".")
    ap.add_argument("--no-cache", default="on", choices=["on", "off"])
    args = ap.parse_args()

    handler = functools.partial(PreviewHandler, directory=args.directory)
    PreviewHandler.no_store = args.no_cache == "on"

    with ThreadingServer((args.bind, args.port), handler) as httpd:
        print("Healer Boy's preview server")
        print("  serving : %s" % args.directory)
        print("  address : http://%s:%d" % (args.bind, args.port))
        print("  demo    : /demo   (one-click demo register)")
        print("  cache   : %s" % ("no-store (always fresh)" if PreviewHandler.no_store else "normal"))
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nbye")


if __name__ == "__main__":
    main()
