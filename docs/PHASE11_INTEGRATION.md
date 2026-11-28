# Phase 11 — combined PCM, AoA and live camera path

Status: technical single-source integration passed on the PYNQ-Z2. Physical
AoA calibration and camera-relative accuracy remain open with Phases 9/10.

## Data path

The source is the official PYNQ-Z2 Base at PYNQ v3.1.2 commit
`3c77124d86bab65ac7bb6beb0aa66e13c83508f2`, copied into an isolated build
directory. The generated Block Design is pruned before synthesis. The retained
fabric is PS7/DDR, the HDMI OUT hierarchy and MM2S framebuffer path on HP0,
plus four-channel PCM, AXI DMA and control on HP2 at FCLK3 (100 MHz). PCM
control remains at `0x43C80000`; DMA control remains at `0x40400000`.

HDMI IN, the four MicroBlaze IOPs, trace analyzers, shared GPIO routing, audio
codec, switches, buttons, LEDs and their AXI paths are removed. The output
crossbar is reduced to its six used targets; the PCM control path uses one
FCLK3 master slot, and HP2 has only the two PCM DMA masters. The PS DDR/MIO
preset, HDMI OUT pins and FCLK0/1/2/3 rates are retained. HDMI OUT uses the
existing packaged HLS cores `color_convert` and `pixel_unpack`; this build
reuses and checks those packages without rerunning Vitis HLS. Cached catalog
packages for Base IP that is removed are staged only so Vivado can load the
original Base hierarchy before pruning; those IP blocks are not synthesized.
Pmod B is reserved for the existing PDM pin map in `src/con/pynq_z2_pcm.xdc`.

The C920 remains a PS/UVC source. On the PS, the Phase 11 runtime reads the
current camera frame while a worker reads continuous PCM, detects a stable
1–3 kHz source, and runs the provisional four-channel AoA estimate. Each new
camera frame receives a red marker only while a recent estimate has status
`VALID_PROVISIONAL`; no center/default point is substituted when AoA is absent
or rejected. The frame is exported from the PS framebuffer immediately before
it is submitted to HDMI OUT. HDMI IN loopback is not required for this check.

The channel map Mic1→PCM0, Mic2→PCM1, Mic3→PCM2, Mic4→PCM3 and the reported
50 × 50 mm square concentric with the camera are inputs to the provisional
estimator. They are not established physical calibration. No physical angle
accuracy claim follows from a red marker or a synthetic test.

## Build

With the pinned PYNQ v3.1.2 source checkout and Vivado 2024.2 installed:

```bash
PYNQ_SOURCE=/path/to/PYNQ-v3.1.2
OUTPUT_DIR=../../acoustic-camera/builds/phase11-combined-$(date -u +%Y%m%dT%H%M%SZ)
scripts/build_phase11_combined.sh "$PYNQ_SOURCE" "$OUTPUT_DIR"
```

Run this from the HW repository root. The output path is relative to the
invocation directory; when using a worktree under `acoustic-camera-worktrees/`,
the example keeps generated projects, bitstreams and reports in the main
workspace's `acoustic-camera/builds/` directory instead of creating a separate
`acoustic-camera-worktrees/builds/` tree. The script also accepts an explicit
absolute output path.

The script creates an isolated source copy, adjusts only that copy for Vivado
2024.2, reuses the packaged HDMI OUT HLS cores, adds PCM, then prunes unused
Base hierarchies before synthesis and implementation. Only the reduced design
is synthesized and routed; removed Base IP is not compiled into the bitstream.
The minimal XDC keeps HDMI TX and adds the Pmod B PDM pin/timing constraints.
Vivado's `RuntimeOptimized` route directive is used for the reduced candidate.
The script checks timing and emits a matching `base.bit`/`base.hwh` pair and
logs in the selected output folder.

The first minimal build completed in Vivado 2024.2.2. Routed setup WNS is
`+0.341 ns` with no failing setup endpoints; the `check_timing` gate passed.
The routed design uses 14,291 LUTs (26.9%) and 22,636 registers (21.3%) on the
XC7Z020. The paired candidate and detailed reports are in
`builds/phase11-camera-minimal-20261122T1440/`. These results verify the PL
implementation and timing constraints, not live HDMI output or physical AoA.

## Board/runtime validation

On 2026-11-22 the combined candidate ran on LaZ2 for about 30 seconds with
continuous PCM capture, C920/UVC and HDMI OUT active together. The board ran
PYNQ 3.1.1 with Python 3.10.4. The official Base BIT was loaded before the
candidate test and restored afterward. Candidate hashes are BIT
`22283318f3658de6fa64b63772e307e43bbabf87a7adfb6e4956baba325df0e7` and HWH
`35686539f2282c7f3bbc4c0a8ad3a71359b9f0a24e43436bc75999371fa2f912`.

The run returned 320 PCM packets at 48 kHz; 34 completed packets were drained
by STOP. It recorded zero PCM discontinuities, capture overflows and clips.
Across the same run, the PS submitted 427 HDMI frames at 13.26 FPS; HDMI
submission p95 was 1.14 ms. Packet-processing p95 was 161.7 ms and 68 packets
exceeded the nominal 85.3 ms packet period. The descriptor ring absorbed that
intermittent delay in this run without loss. This demonstrates functional live
coexistence, not a worst-case hard-real-time guarantee.

The first AoA-on-board attempt used the full 16-seed fit on every active
analysis window and caused the capture error flag. The live runtime now uses a
four-seed fit refreshed every 16 analysis windows (about 2.9 updates/s while a
tone is active). A board CPU benchmark measured six such estimates at 519 ms
total, about 86.5 ms each. The updated run completed without a capture error.

The test WAV emitted 1550 Hz from the PC's left stereo speaker and then 2350 Hz
from the right. There were 22 `VALID_PROVISIONAL` AoA windows at 1549.64 Hz
during the left-speaker tone. The right-speaker 2350 Hz stimulus produced no
valid AoA in this run. Another 39 valid windows appeared at 1.38–1.40 kHz; their
source was not isolated, so they are not attributed to either test tone. The
runtime only paints when its recent AoA result is `VALID_PROVISIONAL` and its
projected pixel is in the frame.

The exported PS framebuffer `submitted_000060.png` contains a red circle
centered at pixel `(309, 408)`. This matches the direct projection of the
1549.64 Hz AoA window at sample 221184: azimuth `1.42°`, elevation `−18.09°`,
with the configured provisional 70° × 50° camera FOV. No pixel coordinate was
forced. The frame is the same buffer submitted to HDMI OUT; no HDMI IN capture
or monitor was required. The image and full run report are in
[`board-live evidence`](../../../acoustic-camera/evidence/phase-11/board-live-20261122T204730Z/README.md).

These values show the frame path and an AoA-driven red marker working; they do
not establish the physical location of the PC speaker. The assumed 50 × 50 mm
geometry, reported channel map and camera FOV remain provisional. Phase 9 is
not accepted or closed.

## Subpasos y estado

| Subpaso | Objetivo | Estado | Comprobación de cierre |
|---|---|---|---|
| 11.1 — Diseño combinado mínimo | Podar PYNQ Base, conservar HDMI OUT y añadir PCM continuo en HP2; generar BIT/HWH. | **Completado en PC.** BD, síntesis, ruta, timing y PDF real exportado. | Par BIT/HWH coincidente y `check_timing` pasado. |
| 11.2 — Enlace de software | Configurar runtime PS para adjuntarse a `ps7_0`, usar HP2 y procesar PCM/AoA mientras toma C920 y entrega cuadros a HDMI OUT. | **Implementado y verificado.** 53 pruebas host pasan; el perfil de placa limita el coste AoA. | HWH HP2 de 64 bits comprobado; no dibuja una coordenada por defecto cuando AoA no es válido. |
| 11.3 — Prueba de arranque y convivencia | Cargar el BIT/HWH candidato; iniciar PCM, cámara y HDMI OUT en paralelo. | **Completado en PYNQ.** Una sesión de ~30 s, 320 paquetes PCM devueltos, cero discontinuidades/overflows/clips y 427 cuadros HDMI. | El runtime completó la sesión y exportó cuadros desde PS antes de enviarlos al VDMA; Base oficial restaurada después. |
| 11.4 — Punto desde AoA en vivo | Emitir una fuente, obtener AoA `VALID_PROVISIONAL` y dibujar el círculo únicamente desde esa dirección. | **Completado para el tono izquierdo de 1550 Hz.** 22 ventanas AoA válidas a 1549.64 Hz; el frame 60 tiene el marcador proyectado a `(309, 408)`. | El pixel medido coincide con la proyección matemática del AoA de esa ventana. Coordenadas y ángulo no se declaran físicamente calibrados. |
| 11.5 — Cierre técnico | Guardar frame, reporte, hashes y resultado de la ejecución; registrar límites conocidos. | **Completado.** | Evidencia reproducible archivada; resultados del tono derecho y detecciones no atribuidas quedan explícitos. |

### Alcance del cierre

El usuario priorizó dejar primero lista la integración técnica y ajustar la
localización con mediciones después. Los subpasos 11.1–11.5 están completos
para integración de una fuente tonal: PCM y video convivieron, el PS generó el
marcador desde AoA provisional y el mismo frame se entregó a HDMI OUT. La
posición puede estar desplazada. La prueba del tono derecho de 2350 Hz no
produjo AoA válido y queda registrada como límite del ensayo, sin bloquear la
prueba de una fuente de 1550 Hz. La calibración física, el ajuste de la
detección y la precisión respecto al campo visual pertenecen al trabajo aún
abierto de fases 9/10. No se reutilizó una posición conocida para forzar el
punto.

No se exige eliminar todos los warnings de Vivado. Sí se revisa el reporte CDC
para atender cruces que representen un riesgo funcional para esta combinación;
las clasificaciones restantes se documentan sin perseguir una etiqueta
CDC-clean por sí sola.

## Histórico: primer candidato de composición del punto en PL (2026-11-23)

> Esta sección registra el snapshot R5 del 23 de noviembre de 2026: un único
> marcador rojo cuadrado. No describe el RTL PL actual. El tracker AOA3 y los
> dos marcadores radiales independientes (PDoA rojo, TDoA cian) están descritos
> en [PL PDoA/TDoA](PL_PDOA_TDOA.md). El BIT/HWH AOA3 está generado, pero su
> marcador PL todavía no cuenta con validación en placa.

En ese snapshot, el repositorio contenía un candidato que insertaba
`acoustic_video_marker` después de
`video/hdmi_out/pixel_unpack/stream_out_24` y antes del registro AXI-Stream de
HDMI OUT, donde cada beat representa un píxel de 24 bits. El PS sigue leyendo la C920 por UVC y escribe el
cuadro sin modificar a DDR; una palabra de AXI GPIO (`0x43C90000`) entrega al
PL la coordenada proyectada y la habilitación. El PL aplica el punto al flujo
de píxeles antes de HDMI OUT. El PCM crudo y su DMA no se alteran.

En ese snapshot, el runner conservaba el backend PS usado en el BIT/HWH
aceptado y seleccionaba este candidato con `--marker-backend pl`. El HWH
exponía `acoustic_marker_gpio` en `0x43C90000`. El marcador era una caja
cuadrada roja con radio configurable. El PNG de depuración representaba el
framebuffer PS sin el punto PL y registraba por separado la coordenada
solicitada.

**Build R5 de PC completado (resultado histórico):**
[`builds/phase11-combined-pl-marker-20261123-r5`](../../../acoustic-camera/builds/phase11-combined-pl-marker-20261123-r5/)
contiene el par BIT/HWH, el manifiesto, logs y reportes. Vivado 2024.2.2
completó generación de bitstream con 0 errores DRC. `check_timing` pasó con
WNS `+0.385 ns`, TNS `0` y cero endpoints setup fallidos. El XDC excluye solo
FCLK3→primera etapa del sincronizador GPIO/video; report_cdc reconoce 27
cruces `CDC-3` sincronizados. Las rutas internas del marcador en FCLK1 cumplen
timing. La lógica reduce el comparador por píxel a cuatro rangos de coordenadas.

**Estado físico de R5:** el BIT/HWH se descargó y PYNQ reconoció el overlay en
dos arranques de placa el 24 de noviembre de 2026. En ambos, el runner terminó
antes de iniciar la captura de cámara o HDMI; no llegó a mostrar ni validar el
marcador. El resultado y las excepciones están registrados en
[`results.md`](../../../acoustic-camera/evidence/final-part-02/pl-marker-board-live-20261124T141632Z/results.md).
La compilación AOA3 posterior se documenta en [PL PDoA/TDoA](PL_PDOA_TDOA.md);
la calibración AoA y la validación visual de HDMI siguen pendientes.
