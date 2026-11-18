# Casio FP-1100 / FP-1000 para MiSTer

*[Read in English](README.md)*

Core de MiSTer del **Casio FP-1100** (1982) y de su hermano monocromo, el
**FP-1000**. Es el mismo core que funciona en Poseidon, SiDi y Calypso
([shaeon/fp1100](https://github.com/shaeon/fp1100)), con el marco de MiSTer
alrededor: los dos procesadores con sus ROMs originales, C82-BASIC, CP/M
desde imágenes EDSK y cintas WAV.

Autor: Shaeon (Carlos Palmero).

## Instalación

- Copia el `.rbf` a `/media/fat/_Computer/`.
- Copia el contenido de la carpeta `sd/` a la raíz de la SD (`/media/fat/`):
  deja la ROM en `games/FP1100/boot.rom`, que se carga sola al arrancar el
  core. Es el mismo `FP1100.ROM` de 48K que usan las otras placas con otro
  nombre (ver
  [rtl/fp1100/roms/README.md](https://github.com/shaeon/fp1100/blob/main/roms/README.md)).
- Los discos (`.dsk`, EDSK) y las cintas (`.wav`) pueden ir en la misma
  carpeta. En `rtl/fp1100/tools/` hay conversores de D88, Teledisk, ImageDisk
  y volcados en crudo a EDSK, y de CAS/TZX/TAP a WAV.

## OSD

| Opción | |
|---|---|
| Drive A: / Drive B: | Imágenes EDSK en las dos unidades del FDC pack |
| Load tape | WAV (hasta ~4 MB, va a la SDRAM) |
| **Video** | |
| Aspect ratio, Scandoubler Fx, Scale | Las de siempre de MiSTer |
| Screen 1 display | *400 lines*: el modo Screen 1 (640×400 entrelazado) sale como una imagen de 400 líneas a 31 kHz. *Fields*: cada trama por separado a 15 kHz (para monitores de 15 kHz) |
| Green mode colour | El modo verde del FP-1000 en verde o en blanco |
| H centre / V centre | Centrado para la salida analógica |
| **Machine** (DIP switches, se leen al arrancar: hacer reset tras cambiarlos) | |
| Model | FP-1100 (color) o FP-1000 (monocromo) |
| Text width | 80 o 40 columnas |
| Screen | Modo de pantalla al arrancar (0 = 640×200 color, 1 = 640×400) |
| CMT baud | 1200 o 300 baudios |
| FDC pack | Con o sin controladora de disco |
| SDRAM read | Momento de recoger el dato de la SDRAM. *Early* es lo que llevan las otras placas (`SDRAM_ANTES`); si el BASIC no arranca o salen colores raros, probar *Normal* |
| Load ROM | Cargar otra ROM a mano |
| **Tape** | |
| Tape input | El WAV cargado o el ADC de la placa I/O (casete de verdad) |
| Invert ADC | Dar la vuelta a la señal del ADC si no carga |
| Tape | Play / pausa del reproductor de WAV |
| Tape monitor | Oír la cinta: con el motor en marcha, siempre o nunca |
| Rewind tape | Rebobinar el WAV |

## Teclas

Las del core original (`fp1100_kbd.v`): BREAK = Fin, STOP/CONT = Pausa,
PF0 = F10, KANA = Alt izq., GRAPH = Alt Gr, HOME/CLS = Inicio, INS = Insert,
DEL = Supr.

## Qué cambia respecto a las otras placas

La máquina (`rtl/fp1100`) es un **submódulo y no se toca**. Lo propio de
MiSTer está en `FP1100.sv`:

- **Relojes**: una PLL de 50 MHz con VCO de 800 MHz da 32 MHz (sistema),
  25 MHz (vídeo, relación 25/32 exacta, como en la Poseidon) y 50 MHz para
  `CLK_VIDEO`. El scandoubler de MiSTer necesita al menos 4 ciclos por punto;
  la salida de `fp1100_display` (puntos de 12,5 MHz sobre 25 MHz) se pasa a
  50 MHz, que va en fase con ella.
- **Vídeo**: sale la imagen de 15 kHz de `fp1100_display` por el
  `video_mixer` de MiSTer (scandoubler, HQ2x, scanlines, escalador HDMI). El
  modo Screen 1 de 400 líneas lo saca el propio core a 31 kHz y entonces se
  salta el scandoubler. No hace falta `fp1100_vga` (`VGA_525`).
- **Teclado**: por la línea PS/2 serie de `hps_io` a ~16 kHz hacia
  `fp1100_ps2`, igual que en MiST. Al abrir y cerrar el OSD se sueltan todas
  las teclas.
- **SDRAM**: el mismo controlador, con `VRAM_SDRAM` como en las otras placas.
  `SDRAM_CLK` es `clk_sys` invertido por un registro DDR.
- **Cinta por ADC**: `ltc2308_tape` de la placa I/O en vez de la entrada de
  audio digital de MiST.

## Compilar

Con Quartus 17.0 (`FP1100.qpf`) o `build.bat`. Hay que descargar el
submódulo: `git clone --recursive` o `git submodule update --init`.

Cada `push` compila el core en GitHub Actions (imagen Docker
`raetro/quartus:17.0`) y deja el `.rbf`, los informes y el detalle de tiempos
de la SDRAM (`tools/rutas_sdram.tcl`) en la pestaña *Actions*. Al subir una
etiqueta `v*` se crea además una Release con el `.rbf`.

Para actualizar el core: `git -C rtl/fp1100 pull` y hacer commit del nuevo
puntero del submódulo.

## Créditos

- **T80** (Daniel Wallner, Sorgelig y la comunidad MiST/MiSTer), **uPD7800**
  (David Hunter, del core Super Cassette Vision), **u765** (György
  Szombathelyi, gyurco).
- **eFP-1100** de Takeda Toshiya, el driver FP-1100 de **MAME** y
  **FP-1100_SD**, como referencias.
- El marco de MiSTer (`sys/`, MiSTer-devel, Sorgelig).
- Al **Retro-Wiki FPGA-dev Team**, en especial a Ron, Manuel (teiram), Somhi,
  Roderick, Rampa, Kyp y Benito.

## Licencia

GPL v3, como el core (el marco `sys/` es GPL v2 o posterior). Casio, FP-1000 y
FP-1100 son marcas de sus propietarios.

---

Desarrollado con la ayuda de Claude (Anthropic).
