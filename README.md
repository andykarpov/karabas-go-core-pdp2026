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

Status: checked on Mini G (the console monitor, bootmon, the console on the terminal and on USB,
the OSD). The Go and Mini builds have not been run on a board yet.

## What you need

- A Karabas board with firmware v26111914 or newer.
- An SD card in the usual slot (SD1) with the core file.
- **A second SD card** for the SD2 slot (the slot of the FPGA): it holds the PDP-11 disks. Any size
  will do: the ready disks take the first ~100 MB. Its content is erased.
- A USB or PS/2 keyboard.
- A Linux (or macOS) PC to write the disks to the second card.

## Step 1. Disks on the second SD card

The PDP-11 disks are not files on the card but raw blocks at fixed places, as on a real hard disk.
They are written by `sd-store` from `disks/tools`.

1. Build the tools (needs `gcc` and `make`):

   ```
   cd disks/tools
   make
   ```

2. Unpack the disk images:

   ```
   cd ..
   for f in *.tar.xz; do tar xJf "$f"; done
   ```

   This gives `B0-RK0.dsk`, `B0-RK1.dsk` and the others: `B<bank>-<type><unit>.dsk`.

3. Put the second card into a card reader and find its device name: `lsblk` before and after
   inserting it, for example `/dev/sdc`. **A wrong device erases another disk.** If the system
   mounted partitions of the card, unmount them: `sudo umount /dev/sdc?*`.

4. Write the disks (from `disks`, where the `.dsk` files are). The arguments are the device, the
   disk type, the unit and the bank:

   ```
   sudo tools/sd-store /dev/sdc RK 0 0
   sudo tools/sd-store /dev/sdc RK 1 0
   sudo tools/sd-store /dev/sdc RK 3 0
   sudo tools/sd-store /dev/sdc RK 4 0
   sudo tools/sd-store /dev/sdc RK 5 0
   sudo tools/sd-store /dev/sdc RL 0 0
   sudo tools/sd-store /dev/sdc RL 2 0
   sync
   ```

   Without a fifth argument `sd-store` takes the file `B<bank>-<type><unit>.dsk`. Your own image
   goes as the fifth argument: `sudo tools/sd-store /dev/sdc RK 2 0 mydisk.dsk`.

5. Put the card into the SD2 slot of the board.

The ready disks:

| Disk | Content |
| :--: | --- |
| RK0 | RT-11 v05.07, the boot disk (required) |
| RK1 | MACRO-11 assembler examples and tests |
| RK3 | FORTRAN-11 |
| RK4 | games for the PDP-11 and DVK |
| RK5 | system tests as paper tape images |
| RL0 | FIG-FORTH for RT-11 and standalone |
| RL2 | the RT-11 sources |

RK0 alone is enough to start. Other simh compatible RK05, RL02 and RP06 images work too (type `DB`
for `sd-store`, preferably with the autozap option). `sd-extract` with the same arguments reads a
disk from the card back into a file.

### Banks

A bank is a full set of disks: 8 RK05, 4 RL02, 8 RP06 and a paper tape, 2 GB of the card. The OSD
(**Menu+Esc** > **Disks**) selects bank 0..3 for each type, so one card holds 4 sets to switch
between without rewriting.

### One card for everything

To keep ordinary files on the same card:

1. Partition the card, the first partition of the size you need.
2. In the OSD (**Disks** > **SD2 offset**) set the offset larger than that partition.
3. Give `sd-store` the bank shifted by the offset: every 8 GB of offset adds 4 to the bank number.

| SD2 offset | Banks for `sd-store` |
| :--: | :--: |
| 0 | 0 .. 3 |
| 8 GB | 4 .. 7 |
| 16 GB | 8 .. 11 |
| ... | ... |
| 56 GB | 28 .. 31 |

Example: a 16 GB card, the first partition 7.9 GB, SD2 offset 8 GB, banks 4..7.

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

Tetris: write RK0, RK1 and RK4, boot and type `@TETRIS`.

There is no "shutdown": RT-11 writes to the disk at once, so just let the program finish. **F12**
resets the machine back to the console, **F11** (Halt / Run) stops the program and goes to the
console, and a second press continues it where it stopped.

## Paper tape

The paper tape is an area of the card: RT-11 "punches" a tape there (`PC:`) and the absolute loader
of the console reads it. This is how programs and tests run without an OS. Steps 1..4 are needed
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

**Tape bank** (OSD > Disks) selects one of 4 tapes. For the tests, turn on **Front panel** (the
front panel lights over the picture). The tests do not start by themselves after loading; most
start at 200.

1. Punch a test to bank 1 and restart the core (Ctrl+Alt+Backspace, PDP-11/70 in the core menu):

   ```
   COPY RK5:CKBAB0.TAP PC:
   ```

2. Choose **Tape bank** = Bank 1 and load the test (`L 157500`, `S`). The machine stops after
   loading, the green light goes off.
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
- **Halt / Run** (**F11**): the HALT / CONT key of the front panel (above);
- **Console**: Terminal (the built-in VT100) or USB serial (the core serial port on a PC);
- **Colour**: the text colour: Amber, Green or White;
- **Sound**: the terminal bell (HDMI and the audio output);
- **Front panel**: the front panel lights over the picture (also shown while no card is in SD2);
- **Slow CPU**: a slowed down CPU;
- **Disks**: **SD2 offset** and the **RK**, **RL**, **RP**, **Tape** banks.

Ctrl+Alt+Backspace goes back to the core menu.

## Changes from the upstream core

- MCU link v2 and karabas-go-modules: the new OSD, ROM loading, the clock, the core serial port; a
  `src/Makefile` build;
- the terminal fixes of [karabas-go-core-vt100](https://github.com/andykarpov/karabas-go-core-vt100):
  the kl11 receiver divider (text got corrupted at 115200), XON / XOFF handled in the core (nothing
  is lost while the screen scrolls);
- the PDP-11 console on the USB core serial port (OSD **Console**);
- a `RESET` instruction no longer cuts the character on the console line (the bootmon banner came
  out as junk);
- the terminal bell on HDMI and the audio output.

## Build

ISE 14.7: `cd src && make minig` (or `go`, `mini`), `make minig-report`. The modules come from the
`modules` submodule (karabas-go-modules): `git submodule update --init`. `src/make_core.py` is a
link to karabas-go-tools next to this repo. The Go and Mini tops are made from the Mini G top:
`python3 src/tools/mktops.py`. The console UART testbench: `src/sim/tb_wbc_uart_reset.v` (iverilog).

## License

The upstream core has no licence file. The pdp2011 / VT100 sources (`src/rtl/vt100`) are Sytse van
Slooten's: personal, non-commercial use only, their notices unchanged.
