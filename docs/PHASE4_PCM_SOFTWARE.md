# Phase 4.5 software handoff for the candidate build

The companion software now exports `pynq_acoustic_camera.AcousticArray` through
its PCM extension, preserving dispatch to the accepted0xB RAW implementation.
For the new0xF interface it validates identity/rates/settling and HWH DMA length23,
stream/master32 and PS HP0=64. It arms16*N DMA bytes before START, returns a
detached signed24-in-int32 `(N,4)` result, and checks counters, sign extension and
clip counts. Physical capture waits for FILTER_READY; patterns bypass it.
Hardware handles startup; software does not discard another six frames per block.

The API uses bounded waits and DMA-local recovery preserving the filter. Its
metadata records the frozen filter identity/hash and hardware provenance.
Notebook04 is packaged with hardware execution disabled, candidate hashes unset
and no FPGA programming call. It prepares RAW wiring, PCM pattern and acoustic
measurements, plus per-run data/error preservation. The current PCM BUILD_ID
interface target remains `B691CC9C9F6249AD938D2063E4767C54`.

Seventeen local PCM/API/analysis/notebook checks and seven existing RAW checks
passed. The wheel contains matching source bytes for modules, filter and notebook;
it was not installed. [phase4-step5-verification.json](phase4-step5-verification.json)
records provenance. These host checks are not board validation.

Step4.6 can now synthesize/implement the separate PCM BD, check resources, I/O/CDC
constraint coverage and routed timing, and generate/pin the real BIT/HWH pair.
No phase-4 bitstream exists yet. Preserve the RAW accepted candidate and deliver
the real Vivado BD PDF at phase closure. This step changes no HDL or BD sources.
