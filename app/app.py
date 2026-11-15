"""A very basic web app, using only the Python standard library (no pip install needed).

  GET /         -> greeting + the name of the pod that answered
  GET /healthz  -> "ok" (used by Kubernetes probes and the load balancer health check)
"""
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8080  # unprivileged port, so the container does not need to run as root


def greeting():
    # socket.gethostname() is the pod name inside Kubernetes. Refresh the page a
    # few times: different pod names show that the load balancer spreads requests.
    return f"Hello from ugallin! Served by: {socket.gethostname()}"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            status, body = 200, "ok"
        elif self.path == "/":
            status, body = 200, greeting()
        else:
            status, body = 404, "Not found"

        data = (body + "\n").encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    print(f"Listening on port {PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
