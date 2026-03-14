# Raspberry Pi Camera Stream

This folder now includes an HLS setup for a Raspberry Pi Camera Module 3 on Raspberry Pi OS Lite. It keeps the same access pattern over your local network or WireGuard VPN:

```text
http://10.20.20.1:8080/
```

HLS is a better fit than MJPEG for phone playback. You should expect smoother `1280x720 @ 30 fps`, but with a few seconds of latency.

## Files

Current streaming setup:

- `hls_stream.sh` - captures H.264 from the camera and writes HLS files
- `hls/index.html` - simple viewer page
- `hls_stream.service` - systemd unit for the HLS producer
- `hls_http.service` - systemd unit for the HTTP server on port `8080`

Legacy MJPEG setup kept for reference:

- `mjpeg_server.py`
- `mjpeg_server.service`

Optional helper:

- `focus_sweep.sh` - captures still images at several manual focus positions so you can choose the sharpest one

## Install

Install the required packages from Raspberry Pi OS/Debian repositories:

```bash
sudo apt update
sudo apt install rpicam-apps ffmpeg ripgrep
```

Install the HLS services:

```bash
sudo cp /home/milos/scripts/sourdough/hls_stream.service /etc/systemd/system/hls_stream.service
sudo cp /home/milos/scripts/sourdough/hls_http.service /etc/systemd/system/hls_http.service
sudo systemctl daemon-reload
```

If `mjpeg_server` is still running, stop and disable it first so port `8080` is free:

```bash
sudo systemctl disable --now mjpeg_server
```

Enable the new services:

```bash
sudo systemctl enable --now hls_stream hls_http
```

Check service status:

```bash
sudo systemctl status hls_stream --no-pager
sudo systemctl status hls_http --no-pager
```

## Stream URL

Viewer page:

```text
http://10.20.20.1:8080/
```

Direct HLS playlist:

```text
http://10.20.20.1:8080/live.m3u8
```

This should work the same way over WireGuard as long as you can already reach `10.20.20.1:8080` through the VPN.

## Stream Settings

Default HLS settings live near the top of `hls_stream.sh`:

```bash
WIDTH=1280
HEIGHT=720
FPS=30
BITRATE=2500000
SEGMENT_TIME=1
LIST_SIZE=4
```

Lower latency:

- Keep `SEGMENT_TIME=1`
- Keep `LIST_SIZE` small
- Expect some buffering anyway on iPhone/Safari

Higher quality:

- Increase `BITRATE`, for example to `4000000`

After changing `hls_stream.sh`, restart the producer:

```bash
sudo systemctl restart hls_stream
```

## Focus Test Images

To generate sample still images with several manual focus values:

```bash
sudo systemctl stop hls_stream
bash /home/milos/scripts/sourdough/focus_sweep.sh
sudo systemctl start hls_stream
```

The script creates a timestamped folder with JPG files and `summary.tsv`.

## Useful Commands

Restart stream:

```bash
sudo systemctl restart hls_stream hls_http
```

Stop stream:

```bash
sudo systemctl stop hls_stream hls_http
```

View logs:

```bash
sudo journalctl -u hls_stream -n 80 --no-pager
sudo journalctl -u hls_http -n 40 --no-pager
```

## Notes

- Only one process can use the camera at a time.
- If `focus_sweep.sh` is running, the stream producer must be stopped first.
- The HLS viewer is aimed at Safari/iPhone. Other mobile browsers may need a dedicated player app or a different frontend.
