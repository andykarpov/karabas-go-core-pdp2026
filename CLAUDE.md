# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A PDP-11/70 core for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). Fork `andykarpov/karabas-go-core-pdp2026` (public) of `tsybulin/karabas-go-core-pdp2026` (Pavel Tsybulin; no licence file). Remotes: `origin` = the fork, `upstream` = tsybulin: fetch only, never push there, no PR to the author unless the user asks. The default branch of the fork is `main`.

Two PDP-11s fill the chip: the machine (`src/rtl/pdp`: pdp2011 CPU of Sytse van Slooten with FP11, MMU, 22 bit, the DVK-FPGA style board `topboard22`, RK11 / RL11 / RH70 and the PC11 paper tape on image files of SD1 (below), KW11, console `wbc_uart`) and its console terminal (`src/rtl/vt100`: Sytse's PDP2011 vt10x VT100, the same RTL as core-vt100). The PDP2011 sources are personal, non-commercial use only; keep their notices.

## Rules of the core

The rules of the other karabas-go cores apply: standard video timing with syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, Mini / Mini G drive T3 (`FLASH_CS_N`) = 0, OSD switch number = the `"index"` of the item in `core.json`, Verilog-2001 / VHDL-93 for XST, changes to imported code marked `karabas:`, builds through `src/Makefile`.

- **Ask the user before every check on the board** (and the HDMI capture). Ask before a firmware flash. **Never write or touch the SD2 card of the bench** (the disks of the user; the core does not use SD2 any more). The disk images live in `/pdp11` on SD1 of the bench (rt11.rk, rt11.rl, tape.ptp; the user allows copying them, also the 63 MB RL set, over MSC).
- Heavy builds: Mini G only while working on one feature, all boards for a release.
- Fit: 99 % slices on Mini G. XST `-opt_mode Area` (`karabas_<board>.xst`) and MAP `-lc area` with the options of upstream (cost table 1, `-xt 0`, `src/Makefile`): Speed / cost table 2 did not fit or hung in par. Keep the HDMI audio (user). If it stops fitting: `ENABLE_AUX` 0 (~200 LUT) first.

## Layout

- `modules`: the karabas-go-modules submodule (`kg_mcu2` link v2, `kg_l2_osd_overlay`, `hdmi_tx`, `kg_pll` / `kg_dcm`, `kg_pcm5102`, `kg_sprom` / `kg_tdpram`).
- `src/rtl/karabas_minig_top.v`: the board glue (see its header): `pdp_clocks`, `kg_mcu2` (switches, PS/2, ROM load of `rom/bootmon.rom` into the SRAM, RTC for the TOY, port 0, OSD, AUX debug), the console line (Terminal: `pdp_txd` to the terminal, its tx through `vt_uart_rx` with XON / XOFF taken out and holding the PDP-11 transmitter, `wbc_uart tx_hold`; USB serial: port 0 both ways), the picture in the OSD colour, the front panel LEDs (`icons.v`), the OSD, HDMI with the bell, the PCM5102.
- `src/rtl/karabas_mini_top.v`, `karabas_go_top.v` and the timing part of `karabas_mini.ucf` / `karabas_go.ucf` are made by `src/tools/mktops.py` from the Mini G top / ucf (as core-vt100): change the Mini G top, then run it.
- `src/rtl/ip/ip_mem.v`: the coregen cores of upstream (bootrom, ledfont, sectorbuf) as `kg_sprom` / `kg_tdpram`; their `.hex` from the `.coe` files of `src/rom` (modules `tools/coe2hex.py`). `src/ipcore_dir` is left from upstream (not in the build).
- karabas changes in the upstream RTL: `wbc_uart.v` (`tx_hold`; `wb_rst_i` = the RESET instruction no longer cuts the frame on the line: the bootmon banner came out as junk, upstream too), `topboard22.v` / `pdp_top.v` (`irps_hold`), the terminal fixes in `src/rtl/vt100` (kl11 divider `<`, rts wired, rtscts silo; see core-vt100).
- `src/sim/tb_pdp_img.v` (iverilog, run from `src`: sdspi_img + pdp_img against a model of the SDC side of kg_l2_img: write, read back, no image, past the end).
- `src/sim/tb_wbc_uart_reset.v` (iverilog -g2005 -I ../rtl/inc with `../rtl/pdp/wbc_uart.v`): a RESET in the middle of a frame, then the banner back to back, decoded without a stop bit check.
- Disks (2026-11-19, the idea of the upstream author: a slot per controller with the units at an offset): one kg_l2_img slot per controller, slot 0 RK11, 1 RL11, 2 RH70 / RP06, 3 the PC11 tape (reader and punch share it). The units lie back to back in the file at unit * unit size (RK05 4872 blocks, RL02 40960: a 256 byte sector a block, RP06 340670, tape 200 blocks of words { 0377, byte }), as sd-store wrote them to SD2: the controllers compute the block themselves, their start offsets are 0 now (no banks). `src/rtl/pdp/sdspi_img.v` replaces `sdspi` in each controller (same ports, its own sector buffer: pr11 reads the buffer after it drops sdreq, so the buffer is NOT shared) with `img_in` / `img_out` ports; `topboard22` muxes the `img_out` of the controller that holds `sdack` and adds the slot (`img_req`); `src/rtl/karabas/pdp_img.v` serves it on kg_l2_img (IMG_OUT_LATENCY 3): no image or a block past the end = an error at once. Saved ~750 LUT and the SD2 card. RT-11 needs the unit numbers (RK1 MAC:, RK3 FOR:, RK4 GAM:, RK5 tests): keep a set's units in place.
- `disks/`: `pdp11.tar.xz` (the ready sets: rt11.rk = RK0 1 - 3 4 5 - -, rt11.rl = RL0 - RL2 -, a blank tape.ptp), `tools/mkpack.py` (builds a set from simh .dsk files, `-` = empty unit; RK / RL files always hold all units (the board cannot grow a file: a unit past the end cannot be INITed), empty RL / RP units get the simh bad block table on the last track (zeros there = `?DUP-F-Bad block in system area` on INIT; 2026-11-20 report of the upstream author), the upstream images `B0-*.tar.xz` and `tools` (sd-store and the others: the old SD2 scheme, not needed by the core).

## Build

- `cd src && make minig` (or `go`, `mini`: xst, impl, `.kg`), `make <board>-report`. Release: all three boards, then `python3 make_core.py core.json pdp2026.kg` packs them all (a `make <board>` packs only its board). `make_core.py` is a symlink to `../../karabas-go-tools/make_core/make_core.py`. `karabas_<board>.bin` and `pdp2026.kg` are committed.
- OSD (`core.json`, the switch numbers are those of upstream `soft_switches`): 0 Reset (F12), 1 Continue (F11, the CONT key of the front panel; named so by the author 2026-11-19, it is not a halt toggle), 11 Console (Terminal / USB serial), 8 Colour, 10 Sound, 9 Front panel (LEDs), 2 Slow CPU, page Disks: the F items RK05 / RL02 / RP06 / Paper tape (slots 0..3, dir /pdp11, defaults rt11.rk / rt11.rl / tape.ptp); switches 3..7 (the SD2 offset and banks of upstream) are not used. Look approved by the user 2026-11-19.
- The `$` monitor reads its commands as pairs of characters: a lone CR first shifts the pairs (looks like a line fault, is not).
- DEBUG (`AT+KARABAS=debug:1`, shown in the firmware log with `debug=1`): addr { console, hold, rts, xoff, usb latch, 0, 0, 0, XOFF count }, data { LEDs, USB bytes lost }.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
