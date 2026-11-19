# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A PDP-11/70 core for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). Fork `andykarpov/karabas-go-core-pdp2026` (public) of `tsybulin/karabas-go-core-pdp2026` (Pavel Tsybulin; no licence file). Remotes: `origin` = the fork, `upstream` = tsybulin: fetch only, never push there, no PR to the author unless the user asks. The default branch of the fork is `main`.

Two PDP-11s fill the chip: the machine (`src/rtl/pdp`: pdp2011 CPU of Sytse van Slooten with FP11, MMU, 22 bit, the DVK-FPGA style board `topboard22`, RK11 / RL11 / RH70 on SD2 through its own `sdspi`, KW11, PC11 paper tape, console `wbc_uart`) and its console terminal (`src/rtl/vt100`: Sytse's PDP2011 vt10x VT100, the same RTL as core-vt100). The PDP2011 sources are personal, non-commercial use only; keep their notices.

## Rules of the core

The rules of the other karabas-go cores apply: standard video timing with syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, Mini / Mini G drive T3 (`FLASH_CS_N`) = 0, OSD switch number = the `"index"` of the item in `core.json`, Verilog-2001 / VHDL-93 for XST, changes to imported code marked `karabas:`, builds through `src/Makefile`.

- **Ask the user before every check on the board** (and the HDMI capture). Ask before a firmware flash. **Never write or touch the SD2 card of the bench** (the disks of the user); bench checks are monitor / bootmon / console only unless the user says otherwise.
- Heavy builds: Mini G only while working on one feature, all boards for a release.
- Fit: 99 % slices on Mini G. XST `-opt_mode Area` (`karabas_<board>.xst`) and MAP `-lc area` with the options of upstream (cost table 1, `-xt 0`, `src/Makefile`): Speed / cost table 2 did not fit or hung in par. Keep the HDMI audio (user). If it stops fitting: `ENABLE_AUX` 0 (~200 LUT) first.

## Layout

- `modules`: the karabas-go-modules submodule (`kg_mcu2` link v2, `kg_l2_osd_overlay`, `hdmi_tx`, `kg_pll` / `kg_dcm`, `kg_pcm5102`, `kg_sprom` / `kg_tdpram`).
- `src/rtl/karabas_minig_top.v`: the board glue (see its header): `pdp_clocks`, `kg_mcu2` (switches, PS/2, ROM load of `rom/bootmon.rom` into the SRAM, RTC for the TOY, port 0, OSD, AUX debug), the console line (Terminal: `pdp_txd` to the terminal, its tx through `vt_uart_rx` with XON / XOFF taken out and holding the PDP-11 transmitter, `wbc_uart tx_hold`; USB serial: port 0 both ways), the picture in the OSD colour, the front panel LEDs (`icons.v`), the OSD, HDMI with the bell, the PCM5102.
- `src/rtl/karabas_mini_top.v`, `karabas_go_top.v` and the timing part of `karabas_mini.ucf` / `karabas_go.ucf` are made by `src/tools/mktops.py` from the Mini G top / ucf (as core-vt100): change the Mini G top, then run it.
- `src/rtl/ip/ip_mem.v`: the coregen cores of upstream (bootrom, ledfont, sectorbuf) as `kg_sprom` / `kg_tdpram`; their `.hex` from the `.coe` files of `src/rom` (modules `tools/coe2hex.py`). `src/ipcore_dir` is left from upstream (not in the build).
- karabas changes in the upstream RTL: `wbc_uart.v` (`tx_hold`; `wb_rst_i` = the RESET instruction no longer cuts the frame on the line: the bootmon banner came out as junk, upstream too), `topboard22.v` / `pdp_top.v` (`irps_hold`), the terminal fixes in `src/rtl/vt100` (kl11 divider `<`, rts wired, rtscts silo; see core-vt100).
- `src/sim/tb_wbc_uart_reset.v` (iverilog -g2005 -I ../rtl/inc with `../rtl/pdp/wbc_uart.v`): a RESET in the middle of a frame, then the banner back to back, decoded without a stop bit check.
- `disks/`: the RT-11 images of upstream and `disks/tools` (`sd-store` and the other utilities that write SD2 from a PC).

## Build

- `cd src && make minig` (or `go`, `mini`: xst, impl, `.kg`), `make <board>-report`. Release: all three boards, then `python3 make_core.py core.json pdp2026.kg` packs them all (a `make <board>` packs only its board). `make_core.py` is a symlink to `../../karabas-go-tools/make_core/make_core.py`. `karabas_<board>.bin` and `pdp2026.kg` are committed.
- OSD (`core.json`, the switch numbers are those of upstream `soft_switches`): 0 Reset (F12), 1 Halt / Run (F11, the front panel HALT / CONT), 11 Console (Terminal / USB serial), 8 Colour, 10 Sound, 9 Front panel (LEDs), 2 Slow CPU, page Disks: 3 SD2 offset (Skip of upstream), 4..7 RK / RL / RP / Tape (PC11) bank. Look approved by the user 2026-11-19.
- The `$` monitor reads its commands as pairs of characters: a lone CR first shifts the pairs (looks like a line fault, is not).
- DEBUG (`AT+KARABAS=debug:1`, shown in the firmware log with `debug=1`): addr { console, hold, rts, xoff, usb latch, 0, 0, 0, XOFF count }, data { LEDs, USB bytes lost }.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
