# Casio FP-1100 / FP-1000 for MiSTer

*[Leer en español](README_es.md)*

MiSTer core for the **Casio FP-1100** (1982) and its monochrome sibling, the
**FP-1000**. It is the same core that runs on Poseidon, SiDi and Calypso
([shaeon/fp1100](https://github.com/shaeon/fp1100)), wrapped in the MiSTer
framework: both processors with their original ROMs, C82-BASIC, CP/M from
EDSK images and WAV tapes.

Author: Shaeon (Carlos Palmero).

## Installation

- Copy the `.rbf` to `/media/fat/_Computer/`.
- Copy the ROM to `/media/fat/games/FP1100/boot.rom`. It is the same 48K
  `FP1100.ROM` used by the other boards, just renamed (see
  [rtl/fp1100/roms/README.md](https://github.com/shaeon/fp1100/blob/main/roms/README.md)).
  It loads automatically when the core starts. **ROMs are not included**:
  they are copyright of Casio.
- Disk images (`.dsk`, EDSK) and tapes (`.wav`) can go in the same folder.
  `rtl/fp1100/tools/` has converters from D88, Teledisk, ImageDisk and raw
  dumps to EDSK, and from CAS/TZX/TAP to WAV.

## OSD

| Option | |
|---|---|
| Drive A: / Drive B: | EDSK images in the two drives of the FDC pack |
| Load tape | WAV (up to ~4 MB, stored in SDRAM) |
| **Video** | |
| Aspect ratio, Scandoubler Fx, Scale | The usual MiSTer options |
| Screen 1 display | *400 lines*: Screen 1 (640×400 interlaced) is shown as one 400-line picture at 31 kHz. *Fields*: each field on its own at 15 kHz (for 15 kHz monitors) |
| Green mode colour | FP-1000 green mode in green or white |
| H centre / V centre | Centring for the analog output |
| **Machine** (DIP switches, read at boot: reset after changing them) | |
| Model | FP-1100 (colour) or FP-1000 (monochrome) |
| Text width | 80 or 40 columns |
| Screen | Screen mode at boot (0 = 640×200 colour, 1 = 640×400) |
| CMT baud | 1200 or 300 baud |
| FDC pack | With or without the disk controller |
| SDRAM read | When the SDRAM data is latched. *Early* is what the other boards use (`SDRAM_ANTES`); if BASIC does not boot or colours look wrong, try *Normal* |
| Load ROM | Load another ROM by hand |
| **Tape** | |
| Tape input | The loaded WAV or the I/O board ADC (a real cassette) |
| Invert ADC | Flip the ADC signal if loading fails |
| Tape | Play / pause the WAV player |
| Tape monitor | Hear the tape: with the motor on, always or never |
| Rewind tape | Rewind the WAV |

## Keys

As in the original core (`fp1100_kbd.v`): BREAK = End, STOP/CONT = Pause,
PF0 = F10, KANA = left Alt, GRAPH = Alt Gr, HOME/CLS = Home, INS = Insert,
DEL = Delete.

## What is different from the other boards

The machine (`rtl/fp1100`) is a **submodule and is not modified**. The MiSTer
glue is in `FP1100.sv`:

- **Clocks**: one PLL from 50 MHz with an 800 MHz VCO gives 32 MHz (system),
  25 MHz (video, exact 25/32 ratio, as on the Poseidon) and 50 MHz for
  `CLK_VIDEO`. The MiSTer scandoubler needs at least 4 clocks per pixel, so
  the output of `fp1100_display` (12.5 MHz pixels on 25 MHz) is moved to the
  in-phase 50 MHz clock.
- **Video**: the 15 kHz picture from `fp1100_display` goes through the MiSTer
  `video_mixer` (scandoubler, HQ2x, scanlines, HDMI scaler). The 400-line
  Screen 1 mode is produced at 31 kHz by the core itself and skips the
  scandoubler. `fp1100_vga` (`VGA_525`) is not needed.
- **Keyboard**: through the serial PS/2 line of `hps_io` at ~16 kHz into
  `fp1100_ps2`, as on MiST. All keys are released when the OSD opens or
  closes.
- **SDRAM**: the same controller, with `VRAM_SDRAM` as on the other boards.
  `SDRAM_CLK` is the inverted `clk_sys` through a DDR register.
- **Tape from the ADC**: `ltc2308_tape` on the I/O board instead of the
  digital audio input of MiST.

## Building

With Quartus 17.0 (`FP1100.qpf`) or `build.bat`. The submodule is needed:
`git clone --recursive` or `git submodule update --init`.

Every push builds the core in GitHub Actions (Docker image
`raetro/quartus:17.0`) and leaves the `.rbf`, the reports and the SDRAM
timing detail (`tools/rutas_sdram.tcl`) in the *Actions* tab. Pushing a `v*`
tag also creates a Release with the `.rbf`.

To update the core: `git -C rtl/fp1100 pull` and commit the new submodule
pointer.

## Credits

- **T80** (Daniel Wallner, Sorgelig and the MiST/MiSTer community),
  **uPD7800** (David Hunter, from the Super Cassette Vision core), **u765**
  (György Szombathelyi, gyurco).
- **eFP-1100** by Takeda Toshiya, the **MAME** FP-1100 driver and
  **FP-1100_SD**, as references.
- The MiSTer framework (`sys/`, MiSTer-devel, Sorgelig).
- The **Retro-Wiki FPGA-dev Team**, especially Ron, Manuel (teiram), Somhi,
  Roderick, Rampa, Kyp and Benito.

## Licence

GPL v3, like the core (the `sys/` framework is GPL v2 or later). Casio,
FP-1000 and FP-1100 are trademarks of their respective owners.

---

Developed with the help of Claude (Anthropic).
