# Licence texts that have to live here

Two of the libraries this package ships arrive with no licence text anywhere in
the artefact they come from. This was checked on the arm64 wheel itself, not
inferred from the amd64 source tree:

| Searched | OpenBLAS | Compute Library | libgomp / gfortran / Runtime Library Exception |
|---|---|---|---|
| `torch-2.12.1+cpu.dist-info/licenses/LICENSE` (7158 lines) | 0 | 0 | 0 |
| `torch-2.12.1+cpu.dist-info/licenses/NOTICE` (456 lines) | 0 | 0 | 0 |
| source tree `NOTICE` (456 lines) | 0 | 0 | 0 |

The 7158-line aggregate looks like it should cover everything and does not.
Its single "Arm Limited" match is a copyright line for Arm's *contributions to
PyTorch*, several hundred lines above the first licence text and unrelated to
`libarm_compute.so`. These libraries are vendored in by the wheel build rather
than by PyTorch, and nothing in the wheel accounts for them.

So they are kept here, in this repository, and installed from here. Licence
texts are meant to travel with the binaries they cover; copying them is the
obligation being discharged, not a thing to be avoided.

Both files are **present**, assembled 2026-09-20:

| File | Covers | Licence | Taken from |
|---|---|---|---|
| `OpenBLAS.LICENSE` | `libopenblas-24fd393f.so.0` | BSD-3-Clause | OpenBLAS `v0.3.30` — `LICENSE`, plus `lapack-netlib/LICENSE` |
| `ArmComputeLibrary.LICENSE` | `libarm_compute.so`, `libarm_compute_graph.so` | MIT, and see below | ACL `v52.6.0` — all three of `LICENSES/` |

`build-rr-libtorch` refuses to produce an arm64 package until both files are
present and non-empty. That refusal is deliberate: a `copyright` file with a
gap in it still looks like a `copyright` file, and the gap is then invisible
for as long as nobody goes looking.

Neither file is needed for the amd64 package, which vendors nothing — it is
built from source and links Debian's own libraries.

## Getting the versions right

"The matching release" was doing real work in that table, and for a while it
was an open question. It no longer is: **both libraries state their own version
inside the shipped binary**, so the versions above are read, not inferred.

    strings libarm_compute.so | grep arm_compute_version
        arm_compute_version=v52.6.0 ... Git hash=b'007264fa740de...'
    strings libopenblas-24fd393f.so.0 | grep '^OpenBLAS '
        OpenBLAS 0.3.30 DYNAMIC_ARCH NO_AFFINITY USE_OPENMP

Do that again after any torch bump rather than assuming these carried over. A
licence text from a later release can carry different terms, and the wheel can
re-vendor without PyTorch's version moving much.

## Two things that were not as expected

**The Arm Compute Library is not MIT-only.** The project is offered under MIT
(`Copyright (c) 2016-2025 Arm Limited`), but its `LICENSES/` directory carries
Apache-2.0 and BSD-3-Clause as well, and upstream's README lists vendored
OpenCL headers (Apache-2.0) and half/libnpy/stb (MIT). Our build sets
`opencl=0`, but the binary is stripped and records nothing about which
third-party sources were compiled in. All three texts are therefore included.
Shipping only MIT would have been a guess presented as a fact.

**Upstream's MIT and BSD texts are REUSE templates**, with the copyright line
left as a literal `<year> <copyright holders>` placeholder. MIT requires the
copyright notice to be retained, so a verbatim copy of that template discharges
nothing on its own. The real notices live in per-file SPDX headers that the
stripped binary does not carry, so the header of `ArmComputeLibrary.LICENSE`
records the notice from upstream's own source files. That header is clearly
marked as ours and sits above the verbatim texts, never inside them.

**OpenBLAS bundles LAPACK** and redistributes it under LAPACK's own licence, so
`lapack-netlib/LICENSE` travels with it. Taking only the top-level `LICENSE`
would have left the University of Tennessee and co-authors unattributed.
