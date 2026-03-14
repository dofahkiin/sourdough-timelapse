#!/usr/bin/env python3
import io
import logging
import socketserver
import threading
from http import server

from libcamera import controls
from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput

# Stream settings
STREAM_SIZE = (1280, 720)
STREAM_FPS = 30
STREAM_PORT = 8080

# Focus settings
# Set to None to use continuous autofocus.
# Example manual values for your Camera Module 3:
#   3.3, 3.7, 4.0, 4.5
MANUAL_LENS_POSITION = 4.5


PAGE = """\
<html>
<head>
  <title>Raspberry Pi Camera</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body style="margin:0;background:#111;">
  <img src="/stream.mjpg" style="display:block;width:100%;height:auto;" />
</body>
</html>
"""


class StreamingOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.condition = threading.Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.condition.notify_all()


class StreamingHandler(server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/index.html":
            content = PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", len(content))
            self.end_headers()
            self.wfile.write(content)
            return

        if self.path in ("/", "/stream.mjpg"):
            self.send_response(200)
            self.send_header("Age", "0")
            self.send_header("Cache-Control", "no-cache, private")
            self.send_header("Pragma", "no-cache")
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=FRAME")
            self.end_headers()
            try:
                while True:
                    with output.condition:
                        if output.frame is None:
                            output.condition.wait()
                        frame = output.frame
                    self.wfile.write(b"--FRAME\r\n")
                    self.send_header("Content-Type", "image/jpeg")
                    self.send_header("Content-Length", len(frame))
                    self.end_headers()
                    self.wfile.write(frame)
                    self.wfile.write(b"\r\n")
            except Exception as exc:
                logging.warning("Streaming client disconnected: %s", exc)
            return

        self.send_error(404)
        self.end_headers()

    def log_message(self, format, *args):
        logging.info("%s - %s", self.address_string(), format % args)


class StreamingServer(socketserver.ThreadingMixIn, server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

picam2 = Picamera2()
frame_duration_us = int(1_000_000 / STREAM_FPS)
config = picam2.create_video_configuration(
    main={"size": STREAM_SIZE},
    controls={"FrameDurationLimits": (frame_duration_us, frame_duration_us)},
)
picam2.configure(config)
logging.info("Configured stream: %sx%s @ %s fps", STREAM_SIZE[0], STREAM_SIZE[1], STREAM_FPS)

if MANUAL_LENS_POSITION is None:
    picam2.set_controls({"AfMode": controls.AfModeEnum.Continuous})
    logging.info("Using continuous autofocus")
else:
    picam2.set_controls(
        {
            "AfMode": controls.AfModeEnum.Manual,
            "LensPosition": float(MANUAL_LENS_POSITION),
        }
    )
    logging.info("Using manual focus, lens position=%s", MANUAL_LENS_POSITION)

output = StreamingOutput()
picam2.start_recording(MJPEGEncoder(), FileOutput(output))

try:
    address = ("0.0.0.0", STREAM_PORT)
    server = StreamingServer(address, StreamingHandler)
    logging.info("Starting MJPEG server on http://0.0.0.0:%s", STREAM_PORT)
    server.serve_forever()
finally:
    picam2.stop_recording()
