# Karabas Go PDP-11/70 Core

[Русская версия](README.ru.md)

The PDP-11/70 is a 1975 DEC minicomputer, the top model of the PDP-11 family (in the USSR the
family was cloned as the SM EVM, DVK, Elektronika-60 and many others). This core turns a Karabas
board into one: a CPU with floating point and memory management, RK05, RL02 and RP06 disks, paper
tape, a clock and a front panel with lights. The disks hold the RT-11 operating system with
languages and games.

It is a fork of Pavel Tsybulin's [pdp2026](https://github.com/tsybulin/karabas-go-core-pdp2026). The
CPU is Sytse van Slooten's pdp2011. The screen is a built-in VT100 terminal: a second PDP-11 inside
the same FPGA. A real PDP-11/70 had a separate terminal on its console line, and this one is
connected the same way.

| Board | Core file | Video |
|---|---|---|
| Karabas Go | `src/pdp2026.kg` (one file for all boards) | VGA 640 x 480 |
| Karabas Mini | | HDMI / DVI 640 x 480 |
| Karabas Mini G | | HDMI / DVI 640 x 480 |

Status: checked on Mini G (the console monitor, bootmon, RT-11 booting from RK, writes to the disk,
RL, the paper tape, the console on the terminal and on USB, the OSD). The Go and Mini builds have not been run on a board yet.

## What you need

- A Karabas board with firmware v26111914 or newer.
- An SD card in the usual slot (SD1): it holds the core and the PDP-11 disks. No second card (SD2)
  is needed.
- A USB or PS/2 keyboard.

## Step 1. The core and the disks on the SD card

The PDP-11 disks are files on the same card as the core. Each controller has its own file with
its disks back to back inside: RK0, RK1, ..., like a stack of disk packs in a cabinet.

1. Copy `src/pdp2026.kg` to the root of the card.
2. Make a `pdp11` folder on the card and unpack `disks/pdp11.tar.xz` into it:

   ```
   tar xJf disks/pdp11.tar.xz -C /path/to/the/card
   ```

   (on Windows: 7-Zip). This gives:

   | File | Controller | Disks |
   | --- | --- | --- |
   | `/pdp11/rt11.rk` | RK11 (RK05) | RK0 RT-11 v05.07 (the boot disk), RK1 MACRO-11 examples and tests, RK3 FORTRAN-11, RK4 games, RK5 system tests as paper tape images; RK2 empty |
   | `/pdp11/rt11.rl` | RL11 (RL02) | RL0 FIG-FORTH for RT-11 and standalone, RL2 the RT-11 sources; RL1 empty |
   | `/pdp11/tape.ptp` | PC11 (paper tape) | a blank tape |

The core mounts these files by itself when they are in `/pdp11` under these names. Other files are
chosen in the OSD: **Menu+Esc** > **Disks**.

The unit numbers matter: RT-11 on RK0 assigns `RK1:` to the assembler, `RK3:` to FORTRAN and
`RK4:` to the games when it boots. That is why RK2 is empty in the set rather than left out.

### Your own disks

`disks/tools/mkpack.py` (Python 3) builds a set from separate simh images:

```
python3 disks/tools/mkpack.py rk my.rk  RK0.dsk RK1.dsk - RK3.dsk
python3 disks/tools/mkpack.py rl my.rl  RL0.dsk
python3 disks/tools/mkpack.py rp my.rp  RP0.dsk
python3 disks/tools/mkpack.py ptp my.ptp tape.bin
```

`-` is an empty disk at that place. A set holds up to 8 RK05 (2.4 MB each), 4 RL02 and 8 RP06. A
unit beyond the end of the file is "no disk" for the PDP-11. An RL file is twice the size of its
images: each 256 byte RL02 sector takes 512 bytes. `mkpack.py ptp` without a file makes a blank
tape, with a file a tape of its bytes (up to 51200).

The separate images of upstream are in `disks/B0-*.tar.xz`. `sd-store` and the other tools in
`disks/tools` wrote the disks to a second card in the old scheme; the core needs them no more.

## Step 2. First start

Copy `src/pdp2026.kg` to the root of the SD1 card and choose **PDP-11/70** in the core menu. The
screen shows:

```
PIP.11.70.CONS

000106 000000 000000 000000
$
```

This is the M9312 console: the numbers are registers (in octal, as everything on the PDP-11), `$`
is its prompt.

## The M9312 console

The console takes two-character commands, an octal number right after them and Enter. Upper or
lower case does not matter.

| Command | What it does |
| --- | --- |
| `DK` Enter | boot from RK0 (`DK1` from RK1 and so on) |
| `DL` Enter | boot from RL0 |
| `DB` Enter | boot from RP06 |
| `L 1000` Enter | set the address 1000 |
| `E ` (E and a space) | show the word at the address; the next `E ` shows the next word |
| `D 123456` Enter | write 123456 at the address; the next `D` writes the next word |
| `S` Enter | reset and start at the address |

A PDP-11 word is 16 bits: numbers up to 177777 (higher digits are dropped), word addresses are
even. Example:

```
$L 1000
$D 123456
$L 1000
$E 001000 123456
```

The characters are read in pairs: a stray Enter before a command shifts the pair and the console
answers with a new `$`. Just type the command again.

## Step 3. RT-11

Type `DK` and Enter. RT-11 boots: after its banner comes a dot `.`, the prompt of the OS.

First commands:

| Command | What it does |
| --- | --- |
| `DIR` | the files on the system disk |
| `DIR RK4:` | the files on RK4 |
| `TYPE file` | show a text file |
| `RUN program` | run a program (`.SAV`) |
| `COPY from to` | copy a file |
| `@file` | run a command file (`.COM`) |
| `SHOW` | the system configuration |

Device names: `DK:` is the disk you booted from, `RK0:`..`RK7:` the RK05 disks, `DL0:`..`DL3:` RL02,
`DB0:` RP06, `PC:` the paper tape. Commands can be shortened (`DIR` = `DIRECTORY`).

Tetris: type `@TETRIS` (the games are on RK4, all in the ready set).

There is no "shutdown": RT-11 writes to the disk at once, so just let the program finish. **F12**
resets the machine back to the console, **F11** (Continue) is the CONT key of the front panel: it
continues a halted program.

## Paper tape

The paper tape is a `.ptp` file in the **Paper tape** item: RT-11 "punches" a tape on it (`PC:`)
and the absolute loader of the console reads it. This is how programs and tests run without an OS. Steps 1..4 are needed
only to change the tape.

1. Boot RT-11.
2. List the tapes:

   ```
   DIR RK5:
   ```

3. Punch a tape, for example *BASIC.TAP*:

   ```
   COPY RK5:BASIC.TAP PC:
   ```

4. Restart the core: Ctrl+Alt+Backspace and PDP-11/70 again in the core menu.
5. In the console, run the absolute tape loader at 157500:

   ```
   L 157500
   S
   ```

### Tests

Keeping a file for each tape is handy: make a blank tape (`mkpack.py ptp test.ptp`), put it into
`/pdp11` and choose it in **Paper tape**. For the tests, turn on **Front panel** (the
front panel lights over the picture). The tests do not start by themselves after loading; most
start at 200.

1. Punch a test to the tape and restart the core (Ctrl+Alt+Backspace, PDP-11/70 in the core
   menu):

   ```
   COPY RK5:CKBAB0.TAP PC:
   ```

2. Load the test (`L 157500`, `S`). The machine stops after loading, the green light goes off.
3. Reset the machine (**F12**) and start the test:

   ```
   L 200
   S
   ```

While a test runs, 3 front panel lights blink and every pass rings the bell. The test never ends:
**F12** to leave.

## bootmon

A second boot loader with a menu, in memory at 140000:

```
L 140000
S
```

It prints `PDP-11 MONITOR V1.0` and the prompt `BOOT>`. Commands: `BOOT` (from RK, RL or RP),
`HALT`, `TEST`, `DIAG`, `LIGHTS`, `HELP`.

## The console on a PC

**Console** = **USB serial** moves the PDP-11 console from the built-in terminal to the core serial
port of the board (115200 8N1), the second USB serial port:
`/dev/serial/by-id/usb-Karabas_Go_<serial>-if02` on Linux, `/dev/cu.usbmodem<serial>3` on macOS,
the COM port named "Karabas core serial" on Windows. Any terminal will do, for example:

```
picocom -b 115200 /dev/serial/by-id/usb-Karabas_Go_<serial>-if02
```

The board screen keeps the terminal, but it is not connected to the PDP-11 then.

## OSD

**Menu+Esc** ("Menu" is the Windows key):

- **Reset** (**F12**): reset the machine;
- **Continue** (**F11**): the CONT key of the front panel: continue a halted program;
- **Console**: Terminal (the built-in VT100) or USB serial (the core serial port on a PC);
- **Colour**: the text colour: Amber, Green or White;
- **Sound**: the terminal bell (HDMI and the audio output);
- **Front panel**: the front panel lights over the picture;
- **Slow CPU**: a slowed down CPU;
- **Disks**: the disk files: **RK05**, **RL02**, **RP06**, **Paper tape**.

Ctrl+Alt+Backspace goes back to the core menu.

## Changes from the upstream core

- MCU link v2 and karabas-go-modules: the new OSD, ROM loading, the clock, the core serial port; a
  `src/Makefile` build;
- the terminal fixes of [karabas-go-core-vt100](https://github.com/andykarpov/karabas-go-core-vt100):
  the kl11 receiver divider (text got corrupted at 115200), XON / XOFF handled in the core (nothing
  is lost while the screen scrolls);
- the disks are files on SD1, one per controller (instead of a separate SD2 card and five SD card
  controllers: ~750 LUT less);
- the PDP-11 console on the USB core serial port (OSD **Console**);
- a `RESET` instruction no longer cuts the character on the console line (the bootmon banner came
  out as junk);
- the terminal bell on HDMI and the audio output.

## Build

ISE 14.7: `cd src && make minig` (or `go`, `mini`), `make minig-report`. The modules come from the
`modules` submodule (karabas-go-modules): `git submodule update --init`. `src/make_core.py` is a
link to karabas-go-tools next to this repo. The Go and Mini tops are made from the Mini G top:
`python3 src/tools/mktops.py`. Testbenches (iverilog): the console UART `src/sim/tb_wbc_uart_reset.v`, the disk path
`src/sim/tb_pdp_img.v`.

## License

The upstream core has no licence file. The pdp2011 / VT100 sources (`src/rtl/vt100`) are Sytse van
Slooten's: personal, non-commercial use only, their notices unchanged.
