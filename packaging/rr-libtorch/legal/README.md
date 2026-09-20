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

| File | Covers | Licence | Obtain from |
|---|---|---|---|
| `OpenBLAS.LICENSE` | `libopenblas-24fd393f.so.0` | BSD-3-Clause | `LICENSE` at the root of the OpenBLAS release matching the wheel's build |
| `ArmComputeLibrary.LICENSE` | `libarm_compute.so`, `libarm_compute_graph.so` | MIT | `LICENSE` at the root of the Arm Compute Library release matching the wheel's build |

`build-rr-libtorch` refuses to produce an arm64 package until both files are
present and non-empty. That refusal is deliberate: a `copyright` file with a
gap in it still looks like a `copyright` file, and the gap is then invisible
for as long as nobody goes looking.

Neither file is needed for the amd64 package, which vendors nothing — it is
built from source and links Debian's own libraries.

## Getting the versions right

"The matching release" is doing real work in that table. The vendored
binaries were built by whoever built the wheel, at versions we did not pick,
and a licence text from a later release can carry different terms. If the
exact version cannot be established, record what was used and why in the file
itself as a comment line above the text — an honest approximation that says
so is worth more than a confident wrong one.
