# SiliconPulse

Native macOS menu bar monitor tailored for running local LLMs on Apple Silicon (calibrated for **Apple M5 Ultra**). Runs purely in user space with **no `sudo`** and **no external dependencies**.

## Features
* **Menu Bar Readout** (toggleable live from the Settings panel): GPU %, GPU Wired Memory vs. `iogpu.wired_limit_mb`, live DRAM Bandwidth (`GB/s`), Die Peak Temp, System Power (W), Fan RPM, and CPU %.
* **Dual-Die Memory Bandwidth (`IOReport` `PMP0`/`PMP1` `DCS BW`)**: Real-time `AMCC0` & `AMCC1` Read/Write GB/s to tell decode bandwidth saturation from prefill/stalls.
* **Unified Memory & LLM Headroom**: Stacked breakdown (GPU / Other Wired / Active / Compressed), GPU Wired Ceiling gauge, Swap & Memory Pressure alerts.
* **GPU Compute & Throttling (`IOAccelerator` + `IOReport` + `pmgr`)**: Device/Renderer %, P-state & MHz, GPU Watts (`Energy Model`), `GPU_CLTM` thermal throttling, `GPU_PPM` power cap, and `recoveryCount` (Metal watchdog resets).
* **CPU Topology (`IOReport` `CPU Stats`)**: Split into **Super** vs **Performance** cores with a per-core live heatmap and Die 0 / Die 1 balance.
* **Thermals, Power & Cooling (`AppleSMC`)**: Die Peak/Avg/Hotspot, VRM/Mem, NAND temp, System/GPU/SoC/Mem/Die wattage, and dual fan RPM.
* **Top Memory Processes**: Live top processes by physical footprint (`proc_pid_rusage`).

## Build & Run

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open dist/SiliconPulse.app
```

To print a one-shot telemetry snapshot in the terminal:

```bash
dist/SiliconPulse.app/Contents/MacOS/SiliconPulse --dump
```

To install permanently in `/Applications`:

```bash
cp -R dist/SiliconPulse.app /Applications/
open /Applications/SiliconPulse.app
```
