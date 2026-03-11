# Raspberry Pi Camera Stream

This folder contains a simple HTTP MJPEG stream for a Raspberry Pi Camera Module 3 on Raspberry Pi OS Lite.

Open from iPhone or any browser:

```text
http://10.20.20.1:8080/
```

## Files

Required for the current streaming setup:

- `mjpeg_server.py`
- `mjpeg_server.service`

Optional helper:

- `focus_sweep.sh` - captures still images at several manual focus positions so you can choose the sharpest one

Not used by the current streaming setup:

- `go2rtc.yaml`
- `go2rtc.service`

These were from an earlier approach and can be ignored unless you want to revisit `go2rtc`.

## Install

Install the required package on the Raspberry Pi:

```bash
sudo apt update
sudo apt install python3-picamera2
```

Install the service:

```bash
sudo cp /home/milos/scripts/sourdough/mjpeg_server.service /etc/systemd/system/mjpeg_server.service
sudo systemctl daemon-reload
sudo systemctl enable --now mjpeg_server
```

Check service status:

```bash
sudo systemctl status mjpeg_server --no-pager
```

## Stream URL

Main page:

```text
http://10.20.20.1:8080/
```

Direct MJPEG stream:

```text
http://10.20.20.1:8080/stream.mjpg
```

## Focus

Manual focus is controlled at the top of `mjpeg_server.py`:

```python
MANUAL_LENS_POSITION = 4.5
```

Use `None` for continuous autofocus:

```python
MANUAL_LENS_POSITION = None
```

After changing focus, restart the service:

```bash
sudo systemctl restart mjpeg_server
```

## Focus Test Images

To generate sample still images with several manual focus values:

```bash
sudo systemctl stop mjpeg_server
bash /home/milos/scripts/sourdough/focus_sweep.sh
sudo systemctl start mjpeg_server
```

The script creates a timestamped folder with JPG files and `summary.tsv`.

## Useful Commands

Restart stream:

```bash
sudo systemctl restart mjpeg_server
```

Stop stream:

```bash
sudo systemctl stop mjpeg_server
```

View logs:

```bash
sudo journalctl -u mjpeg_server -n 80 --no-pager
```

## Notes

- Only one process can use the camera at a time.
- If `focus_sweep.sh` is running, the stream service must be stopped first.
- Current stream resolution is `1280x720`.
