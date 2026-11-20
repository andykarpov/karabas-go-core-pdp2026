#!/usr/bin/env python3
"""mkpack.py: the disk image files of the Karabas PDP-11/70 core (one file per controller, put on
the SD card of the board in /pdp11 and chosen in OSD > Disks).

  mkpack.py rk  out.rk  RK0.dsk [RK1.dsk | - ...]    RK05: units 0..7, 4872 blocks each
  mkpack.py rl  out.rl  RL0.dsk [RL1.dsk | - ...]    RL02: units 0..3 (simh images, 10 MB each)
  mkpack.py rp  out.rp  RP0.dsk [RP1.dsk | - ...]    RP06: units 0..7, 340670 blocks each
  mkpack.py ptp out.ptp [tape.bin]                   paper tape: a raw tape, or a blank one

The units of a controller lie back to back in its file, unit n at n * unit size (as sd-store
wrote them to the SD2 card); "-" leaves a unit empty. RK and RL files always hold all the units of
the controller (8 RK05, 4 RL02): the ones not given are empty, so the PDP-11 can INIT them (the
board does not grow a file, a unit past its end is "no disk"). An RP file ends after the last unit
given (an RP06 is 174 MB): list "-" for the empty ones you want. An empty RL02 / RP06, or an image
without its last track, gets the bad block table on the last track as simh writes it to a new
disk (DEC STD 144: serial 012345, then 177777, in the first 10 sectors): without it RT-11 INIT
reads zeros there = a bad block 0 and stops with "Bad block in system area". RL02 sectors are
256 bytes: each takes a 512 byte block (the second half zero), so an RL file is twice the size
of its simh images. The paper tape is
200 blocks of 16 bit words { 0377, byte } (the format of the PC11 reader / punch of the core: a
word without 0377 in its high byte is the end of the tape), at most 51200 bytes of tape.
"""
import struct
import sys

BLOCK = 512
UNITS = {               # blocks a unit, units, bytes of an image, all units, bad block table
    "rk": (4872, 8, 4872 * 512, True, None),
    "rl": (40960, 4, 20480 * 512, True, (40, 256)),      # sectors a track, bytes a sector
    "rp": (340670, 8, 340670 * 512, False, (22, 512)),
}
TAPE_BLOCKS = 200


def die(msg):
    sys.exit("mkpack.py: " + msg)


def bad_block_table(nsec, ssize):
    """The last track as simh pdp11_bad_block() writes it: 10 sectors of
    { 012345, 012345, 0, 0, 177777 ... } (the rest of the track zero)."""
    sector = struct.pack("<4H", 0o12345, 0o12345, 0, 0) + b"\xff" * (ssize - 8)
    n = min(nsec, 10)
    return sector * n + bytes((nsec - n) * ssize)


def pack(kind, out, images):
    usize, nmax, isize, full, bad = UNITS[kind]
    if not images or len(images) > nmax:
        die("%s: 1 to %d units" % (kind, nmax))
    if full:
        images = images + ["-"] * (nmax - len(images))
    with open(out, "wb") as f:
        for n, name in enumerate(images):
            if name == "-":
                data = b""
            else:
                with open(name, "rb") as g:
                    data = g.read()
                if len(data) > isize:
                    die("%s: %d bytes, more than a %s unit (%d)" % (name, len(data), kind, isize))
            if bad and len(data) <= isize - bad[0] * bad[1]:   # no last track
                data = data.ljust(isize - bad[0] * bad[1], b"\0") + bad_block_table(*bad)
            data = data.ljust(isize, b"\0")
            if kind == "rl":   # a 256 byte sector a block
                data = b"".join(data[i:i + 256] + bytes(256) for i in range(0, len(data), 256))
            f.write(data.ljust(usize * BLOCK, b"\0"))
            print("%s unit %d: %s" % (kind.upper(), n, name if name != "-" else "(empty)"))
    print("%s: %d bytes" % (out, len(images) * usize * BLOCK))


def tape(out, src):
    data = b""
    if src:
        with open(src, "rb") as g:
            data = g.read()
    if len(data) > TAPE_BLOCKS * BLOCK // 2:
        die("%s: %d bytes, the tape holds %d" % (src, len(data), TAPE_BLOCKS * BLOCK // 2))
    words = b"".join(bytes((b, 0o377)) for b in data)
    with open(out, "wb") as f:
        f.write(words.ljust(TAPE_BLOCKS * BLOCK, b"\0"))
    print("%s: %s, %d bytes of tape" % (out, src or "blank", len(data)))


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    kind, out = argv[1].lower(), argv[2]
    if kind in UNITS:
        pack(kind, out, argv[3:])
    elif kind == "ptp":
        tape(out, argv[3] if len(argv) > 3 else None)
    else:
        die("unknown type %s (rk, rl, rp, ptp)" % kind)


if __name__ == "__main__":
    main(sys.argv)
