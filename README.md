# KRM Weigh Scale Integration

A lightweight VBScript service that periodically polls a weigh-scale REST API,
extracts the weight reading, and appends non-idle readings (with a timestamp)
to a log file.  Designed to run unattended as a Windows service via
[NSSM](https://nssm.cc/).  No external runtime or dependencies required —
VBScript is built into every modern version of Windows.

---

## Files

| File | Purpose |
|------|---------|
| `main.vbs` | Application entry-point |
| `config.ini` | Runtime configuration (URL, interval, log path) |
| `weight_log.txt` | Generated log file (created automatically) |

---

## Configuration (`config.ini`)

```ini
[settings]
api_url                 = http://localhost:8080/api/weight/get-weight
poll_interval_seconds   = 5
log_file                = weight_log.txt
request_timeout_seconds = 10
```

| Key | Default | Description |
|-----|---------|-------------|
| `api_url` | `http://localhost:8080/api/weight/get-weight` | Full URL of the weight API |
| `poll_interval_seconds` | `5` | How often (seconds) to query the API |
| `log_file` | `weight_log.txt` | Log file path (relative = next to `main.vbs`) |
| `request_timeout_seconds` | `10` | HTTP request timeout |

---

## Prerequisites

* Windows (XP or later) — no additional software required.

---

## Running manually

Open a command prompt in the script directory and run:

```bat
cscript main.vbs
```

> **Note:** Use `cscript.exe` (not `wscript.exe`) so that log output is
> printed to the console.  The script runs in an infinite loop, polling every
> `poll_interval_seconds` seconds.  Press **Ctrl+C** to stop.

---

## Sample API response

```json
{"success": true, "weight": "\u00021      00    00", "port": "COM3"}
```

The `\u0002` prefix (`STX` control character) is the scale's idle / no-load
sentinel.  The script silently ignores readings that match this value and only
writes to the log when an actual weight is detected.

---

## Log format

```
2024-03-15 09:22:31  Weight: <value>
```

---

## Installing as a Windows service with NSSM

1. Download **NSSM** from <https://nssm.cc/download> and place `nssm.exe`
   somewhere on your `PATH` (e.g. `C:\Tools\nssm.exe`).

2. Open an **elevated** command prompt and run:

   ```bat
   nssm install KRMWeighScale "C:\Windows\System32\cscript.exe" "C:\KRMWeighScaleIntegration\main.vbs"
   ```

3. Configure the working directory (so `config.ini` is found automatically):

   ```bat
   nssm set KRMWeighScale AppDirectory "C:\KRMWeighScaleIntegration"
   ```

4. (Optional) Route stdout/stderr to files for easier debugging:

   ```bat
   nssm set KRMWeighScale AppStdout "C:\KRMWeighScaleIntegration\service_stdout.log"
   nssm set KRMWeighScale AppStderr "C:\KRMWeighScaleIntegration\service_stderr.log"
   ```

5. Start the service:

   ```bat
   nssm start KRMWeighScale
   ```

6. To remove the service later:

   ```bat
   nssm remove KRMWeighScale confirm
   ```
