# Port del FP-1100 a MiSTer — progreso

Para retomar con "sigue".

## Hecho (18/11/2026)

- Estructura MiSTer copiada de Lynx_MiSTer (`sys/` de la misma versión, qsf, workflow,
  `build.bat`, `clean.bat`, `tools/rutas_sdram.tcl`).
- `rtl/fp1100`: submódulo shaeon/fp1100 (sin cambios). `files.qip` usa su `rtl/` y
  `common/T80`; no su `common/mist-modules` (chocaría con `sys/`).
- `FP1100.sv` (emu): PLL 32/25/50 MHz (VCO 800), hps_io (VDNUM 2, PS/2 serie a ~16 kHz hacia
  `fp1100_ps2`), carga de boot.rom (índice 0) y WAV (índice 2) con `ioctl_wait`, ADC con
  `ltc2308_tape`, vídeo pasado de clk_pix a clk_vid para `video_mixer`, `video_freak`, audio,
  LEDs, `OSD_STATUS` para soltar teclas.
- `VRAM_SDRAM=1` como en las otras placas. `SDRAM_ANTES` es opción del OSD ("SDRAM read",
  Early por defecto = como las otras placas).
- Compilado con Quartus 17.0 Lite en el contenedor (ver abajo el resultado).
- README en inglés y español.
- `sd/games/FP1100/boot.rom`: la ROM (FP1100.ROM de 48K, comprobada con los SHA1 de MAME).

## Arreglado (22/11/2026): pantalla en negro

- Síntoma: OSD y vsync, pero imagen negra; el Z80 no arrancaba.
- Diagnóstico (RBF con la ROM del Z80 copiada en block RAM y comparando cada lectura): el Z80
  leía 01 01 FF FF en vez de AF 01 80 FF, el byte impar en cada dirección par, con Early y con
  Normal. Las escrituras de un byte pisaban los dos bytes de la palabra.
- Causa: en algunos módulos SDRAM de MiSTer DQML/DQMH van unidas a A11/A12; la máscara tiene
  que ir en A12:A11 en el WRITE. Arreglado en FP1100.sv (el submódulo no cambia). Reproducido y
  comprobado en simulación con un modelo de SDRAM así.

## Pendiente (probar en la placa)

- Que arranque el BASIC con "SDRAM read = Early"; si no, probar "Normal" y dejar el que
  funcione por defecto.
- Colores (texto blanco, no cian) y Screen 1 en 400 líneas y en Fields.
- Teclado (teclas pegadas, Pausa = STOP/CONT, Fin = BREAK).
- Cinta: WAV y ADC (si no carga por el ADC, probar "Invert ADC" y dejar el bueno por defecto).
- Discos EDSK en A y B, CP/M.
- Scandoubler / HQ2x / scanlines en salida analógica y el centrado H/V a 15 kHz.
