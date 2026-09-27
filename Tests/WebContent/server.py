import http.server
import json
import pathlib
import sys

counts = {}
count_file = pathlib.Path(sys.argv[2])

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        counts[self.path] = counts.get(self.path, 0) + 1
        temporary = count_file.with_suffix('.tmp')
        temporary.write_text(json.dumps(counts))
        temporary.replace(count_file)
        self.send_response(200)
        if self.path.endswith('/script'):
            kind, body = 'application/javascript', b'window.regressionScriptLoaded=true;'
        elif self.path.endswith('/style'):
            kind, body = 'text/css', b'body { color: black; }'
        else:
            kind, body = 'text/html', b'<!doctype html><title>Local regression fixture</title>'
        self.send_header('Content-Type', kind)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
