# Construcción trazable de la referencia XADC

Preparado en el paso 1.3 (2026-11-10). **El flujo no se ha ejecutado con Vivado todavía.** Su primera construcción y revisión corresponden a 1.4. La adquisición sigue siendo la referencia XADC dual; no se implementa PDM en este cambio.

## Requisitos

- Python 3.8+ y Git; el wrapper solo usa la biblioteca estándar.
- Vivado **2024.2.2** disponible en PATH o indicado con `--vivado`, con sus licencias/IP y entorno preparado.
- Repositorio y submódulos inicializados, en los commits registrados y sin cambios ni archivos sin seguimiento. Los cambios de este paso deben estar comprometidos antes de construir.
- Espacio para una copia Git independiente, sus submódulos y las salidas Vivado por ejecución. No se reutiliza una implementación anterior.
- `HOG_EXTERNAL_PATH` y `HOG_IP_PATH` sin definir o vacíos: este primer flujo rechaza dependencias de diseño externas o cachés de IP no incluidas en su procedencia.

## Comando para el paso 1.4 — no ejecutado en 1.3

Desde la raíz de este repositorio, con el entorno de Xilinx disponible:

```bash
python3 scripts/build_reference.py
```

Para señalar el ejecutable conocido de este computador:

```bash
python3 scripts/build_reference.py \
  --vivado /home/siriricomun/tools/Xilinx/Vivado/2024.2/bin/vivado
```

La ruta de instalación contiene `2024.2`; se exige que el ejecutable reporte `2024.2.2`. Opcionalmente, `--builds-dir /ruta/externa/builds` cambia la salida. No se admiten salidas dentro del repositorio de trabajo. No se usan opciones para ignorar un árbol sucio o cambiar automáticamente de versión.

## Secuencia y separación de salidas

1. Capturar commit fuente S y gitlinks de todos los submódulos, comprobando que estén inicializados y limpios.
2. Crear `../builds/<UTC>-<commit12>-<id>/` sin sobrescribir ejecuciones anteriores. Registrar `build-request.json` y la versión efectiva de Vivado.
3. Clonar S y los submódulos desde sus copias locales con `--no-hardlinks`, sin worktrees compartidos ni alternates. Los módulos quedan en sus SHA fijados. No se necesitan credenciales para esta copia local.
4. Dentro de esa copia, ejecutar `Hog/Do CREATE pynq_z2` y después `Hog/Do WORK pynq_z2`. Hog conserva su ruta convencional `Projects/pynq_z2`; queda dentro de la ejecución aislada, sin modificar el submódulo Hog.
5. Después de que WORK termine, abrir el `.xpr` generado mediante un proceso Vivado batch separado. Exigir parte/top esperados, `write_bitstream` completado e implementación que no necesite refresh. Abrir `impl_1` y generar informes de timing, utilización y DRC.
6. Exportar un único `reference.xsa` con `write_hw_platform -fixed -include_bit`. El script Tcl no selecciona ningún HWH de `src/bd/hw_handoff` ni busca archivos antiguos en `bin/`.
7. Extraer exactamente un BIT y un HWH de ese XSA a nombres fijos `pynq_z2.bit` y `pynq_z2.hwh`. Rechazar archivo vacío, selección ambigua, XML inválido o BIT cuyo hash/tamaño no coincida con el de la implementación terminada.
8. Revalidar HEAD, limpieza y submódulos tanto de la fuente de trabajo como de la copia construida. Crear manifiesto/checksums y promover la carpeta temporal a `artifacts/` únicamente al terminar el empaquetado.

La exportación posterior a WORK evita ejecutar `write_hw_platform` desde el hook mientras `write_bitstream` todavía termina. El hook anterior ya no copia ni reemplaza artefactos. Se conservan los comandos GUI de exportación de diagramas, pero CREATE deja de ejecutarlos automáticamente porque modificaban documentación versionada.

## Estructura de cada ejecución

```text
builds/<run-id>/
├── build-request.json
├── vivado-version.txt
├── source/                  # clon independiente; Projects/ y salida interna de Hog
├── clone.log, module-*.log, create.log, work.log
├── export.log, export-vivado.log, export-vivado.jou
├── export/
│   ├── reference.xsa
│   └── export-receipt.tsv
└── artifacts/               # solo aparece tras completar el empaquetado
    ├── pynq_z2.bit
    ├── pynq_z2.hwh
    ├── build-manifest.json
    ├── SHA256SUMS.txt
    └── reports/
        ├── timing_summary.rpt
        ├── utilization.rpt
        └── drc.rpt
```

En fallo se conserva la ejecución y `failure.json`; una carpeta `.artifacts-stage/` parcial no es un paquete válido. No retomar esa carpeta para combinar resultados: corregir las fuentes, registrar un nuevo commit y construir en otra ejecución.

## Manifiesto y aceptación

`build-manifest.json` registra S, limpieza, submódulos, fecha UTC, identificador de ejecución, versión observada, placa/parte/top, hashes/tamaños del BIT/HWH, referencia/hash del XSA y de los informes. `SHA256SUMS.txt` enumera BIT, HWH y manifiesto, sin incluirse a sí mismo. El manifiesto tampoco contiene su propio hash.

`interface_id = legacy-xadc-reference/1` es una etiqueta de metadatos de la referencia; **no** afirma una ABI PDM ni un identificador verificable en registros. `build_id_128 = null`, porque el diseño legado no implementa BUILD_ID. Su comprobación en registros empieza con el diseño de fase 2.

El empaquetador no determina aceptación del timing ni calidad de adquisición: `implementation_report.review_status = not_performed_by_packager` y `physical_validation = not_run`. En 1.4 se deben revisar los informes, caminos sin restricción, CDC/reset, warnings y recursos; un comando que termine correctamente no acepta automáticamente el hito. La placa seguirá pendiente para 1.8–1.9.

El flujo verifica procedencia por ejecución y contenido, no promete binarios idénticos entre dos construcciones de Vivado.

## Publicación posterior, fuera de 1.3–1.4

El wrapper no modifica `bin/`, no crea tags, no sube archivos, no programa FPGA y no instala software. Los BIT/HWH ya versionados en `bin/` siguen siendo referencias históricas, nunca entradas de la nueva construcción.

En 1.5 se seleccionará una construcción aceptada y se preparará el commit de empaquetado R con `bin/pynq_z2.bit`, `bin/pynq_z2.hwh` y `bin/build-manifest.json`. Las fuentes, scripts, BD, restricciones y submódulos entre S y R deben seguir iguales. `.gitignore` deja visibles esos tres nombres y mantiene ignoradas las demás salidas. El workflow de publicación todavía es el heredado y requiere adaptación en 1.5.

Conservar XSA, informes y logs como evidencia local de la ejecución. Antes de publicar logs o datos del entorno, revisar su contenido; el wrapper no vuelca variables ni guarda credenciales en el manifiesto.

## Referencia técnica y comprobaciones pendientes

La documentación oficial describe `write_hw_platform` como exportación del diseño y `-include_bit` como inclusión de su bitstream: [AMD UG835, write_hw_platform](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/write_hw_platform). La aplicación exacta a Vivado 2024.2.2 y al BD de este proyecto se comprobará en 1.4, especialmente propiedades de runs y contenido del XSA. Una composición de XSA inesperada debe producir error, no una elección silenciosa entre handoffs.

En 1.3 solo se preparó y revisó estáticamente el código; no se ejecutaron tests funcionales, Hog, Vivado ni esta herramienta de construcción.
