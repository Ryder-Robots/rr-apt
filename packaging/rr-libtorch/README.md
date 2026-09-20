# rr-libtorch

The PyTorch C++ runtime `rr-emod-serde` links against, as a Debian package, so
`librr_emod_serde.so` stops resolving to three `not found` lines and the brain
can be installed rather than staged.

    ldd /usr/lib/aarch64-linux-gnu/librr_emod_serde.so | grep 'not found'
        libtorch.so => not found
        libc10.so => not found
        libtorch_cpu.so => not found

Upstream **2.12.1** on both architectures. This is our repository, not a
product, so the procedure below names our machines and our paths rather than
pretending to be general.

## Procedure

Build natively, on the machine whose architecture you want. The `.deb` is
~300 MB and is never committed — `.gitignore` carries `**.deb`.

### amd64, on rr-llm

The source is Aaron's own PyTorch build, not a download:
`~/code/pytorch` at tag `v2.12.1`, installed to `~/libtorch-build`. Its
licence texts come from the source tree, which the build finds by itself.

    cd ~/ws/rr-apt/packaging/rr-libtorch
    ./build-rr-libtorch -n        # read the copyright it would install
    ./build-rr-libtorch           # ~/var/rr-deb/amd64/rr-libtorch_2.12.1-1_amd64.deb

Expect three libraries and `libopenblas0` among the dependencies — a source
build links Debian's OpenBLAS by its ordinary soname.

### arm64, on rr-pi

The source is the PyPI wheel `torch 2.12.1+cpu`, reached through the filtered
view built on 2026-09-13:

    ~/libtorch-build/include          # real directory, protobuf headers and protoc excluded
    ~/libtorch-build/lib   -> ~/torch-venv/lib/python3.13/site-packages/torch/lib
    ~/libtorch-build/share -> ~/torch-venv/lib/python3.13/site-packages/torch/share

Licence texts come from `torch-2.12.1+cpu.dist-info/licenses/`, which the build
also finds by itself. Everything else it needs — `objdump`, `dpkg-shlibdeps`,
`dpkg-deb` — is already installed there.

    rsync -a ~/ws/rr-apt/packaging/rr-libtorch/ rr-pi.rrobots.lan:~/rr-libtorch/
    ssh rr-pi.rrobots.lan 'cd ~/rr-libtorch && ./build-rr-libtorch'
    scp rr-pi.rrobots.lan:~/var/rr-deb/arm64/*.deb ~/var/rr-deb/arm64/

Expect six libraries. **This will refuse until `legal/OpenBLAS.LICENSE` and
`legal/ArmComputeLibrary.LICENSE` exist** — see `legal/README.md`.

> `rr-pi.rrobots.lan` is the copper leg (.144) and may not be in `known_hosts`
> after the 2026-09-20 VLAN move. `rr-pi-wifi.rrobots.lan` (.145) is the dev
> leg and works today.

### Publish

    rr-apt-add ~/var/rr-deb/<arch>/rr-libtorch_2.12.1-1_<arch>.deb

Per-architecture, as always — a bare `reprepro remove` drops every
architecture at once.

## When torch updates

Nothing here is pinned to 2.12.1. Re-point `-s` at the newer tree and run the
same two commands; the package follows by itself:

| | comes from |
|---|---|
| version | `share/cmake/Torch/TorchConfigVersion.cmake` in the tree |
| payload | a DT_NEEDED walk from the three roots |
| dependencies | `dpkg-shlibdeps` against the target's package database |
| licence texts | the tree's own, plus `legal/` for what it doesn't carry |

The version deliberately comes from CMake's config rather than a constant in
the script or the wheel's `dist-info`. It is the one place the two artefacts
agree: `dist-info` says `2.12.1+cpu`, the source tree says nothing at all, and
both ship that file with `2.12.1` in it. So one bump produces one version
string on both architectures, which is what keeps the golden image consistent
with whatever `rr-emod-serde` was built against.

`-V` overrides it if upstream ever moves that file, and refuses anything that
is not a usable Debian version — a typo there would install and then sort
wrongly for the rest of the package's life.

What a torch bump **will** need a human for: re-checking `legal/`. A new wheel
can vendor a different OpenBLAS, or pick up something new entirely. The build
refuses on a missing text but cannot notice a stale one, so compare
`PROVENANCE` against the previous release before publishing.

## What the build works out for itself

Nothing per-architecture is hardcoded, which is what lets one script produce
three libraries on rr-llm and six on rr-pi:

- **What to ship** — it walks DT_NEEDED from `libtorch.so`, `libc10.so` and
  `libtorch_cpu.so`, keeps whatever the tree itself provides, and turns
  everything else into a dependency.
- **Which artefact this is** — `source` or `wheel`, decided by looking for a
  mangled `libopenblas-*.so.0`, and recorded in `PROVENANCE`. "libtorch 2.12.1"
  on its own does not say what is inside the file.
- **Dependencies** — `dpkg-shlibdeps` against the target's own package
  database, which is the reason the build is native.

It refuses, rather than producing something plausible, when:

| | |
|---|---|
| a licence text for a vendored library is missing or empty | the `copyright` would have a silent gap |
| PyTorch's `LICENSE` and `NOTICE` cannot be found | the same, for the part every build needs |
| `dpkg-shlibdeps` fails, or returns a `Depends` without `libc6` | shlibdeps can exit 0 having resolved nothing, and the package then installs cleanly on a box that cannot run it |

`-n` stages everything and prints the generated `copyright` and `PROVENANCE`
in full, then builds nothing.

## What it ships, and what it does not

Into a private prefix, `/usr/lib/rr-emod/libtorch/`:

| Shipped | Why |
|---|---|
| `libtorch.so` `libc10.so` `libtorch_cpu.so` | what the brain links |
| `libopenblas-24fd393f.so.0` | arm64 only — `libtorch_cpu.so` needs it by that exact mangled soname, so only the wheel's copy satisfies it |
| `libarm_compute.so` `libarm_compute_graph.so` | arm64 only — no Debian package provides these |

Two are **deliberately not shipped**, and become `Depends` instead:

| Not shipped | Provided by |
|---|---|
| `libgomp.so.1` | `libgomp1` |
| `libgfortran.so.5` | `libgfortran5` |

Both arrive vendored in the arm64 wheel, and both are **GPL-3 with the GCC
Runtime Library Exception**. `objdump -p libtorch_cpu.so` shows it needs them
by their ordinary sonames, not mangled ones, so Debian's copies satisfy the
link exactly — and rr-pi already has `libgomp1 14.2.0-19` and
`libgfortran5 14.2.0-19`. Depending rather than copying keeps the only GPL
obligation in the closure where it already sits, with Debian, and leaves this
package BSD-3 and MIT throughout.

`libopenblas` cannot be handled the same way. auditwheel renamed it to
`libopenblas-24fd393f.so.0` and wrote that name into `libtorch_cpu.so`'s
DT_NEEDED, so Debian's `libopenblas0` does not satisfy it without patching the
binary. Not worth the risk for the size saved.

### Why a private prefix and not /usr/lib

Nothing here goes on the dynamic linker's search path, and the package installs
**no** `/etc/ld.so.conf.d` fragment. A vendored library in the linker cache is
resolvable by every process on the box, which is how an unrelated program ends
up running PyTorch's build of something instead of Debian's. Confining the
lookup to the one consumer that wants it is the whole point.

## The one change outside this directory

The consumer finds the libraries through RPATH, which lives in
`rr-emod-serde`'s `CMakeLists.txt`:

    set_target_properties(rr_emod_serde PROPERTIES
        INSTALL_RPATH "/usr/lib/rr-emod/libtorch")

Without it this package installs correctly and changes nothing — the three
`not found` lines stay.

## Legal documentation

This was missing, and missing badly: the installed libtorch tree on rr-llm
contains **exactly one** licence file (`share/doc/dnnl/LICENSE`). PyTorch's own
`LICENSE` and `NOTICE` are not installed by `cmake --install`, so packaging the
tree as-is would redistribute BSD-3-Clause code without the notice the licence
requires us to retain.

Worse, nothing that arrives with either artefact describes the vendored
libraries. Measured on both:

| | OpenBLAS | Compute Library | libgomp / gfortran |
|---|---|---|---|
| source tree `NOTICE` (456 lines) | 0 | 0 | 0 |
| wheel `licenses/LICENSE` (7158 lines) | 0 | 0 | 0 |
| wheel `licenses/NOTICE` (456 lines) | 0 | 0 | 0 |

The wheel's aggregate has one "Arm Limited" hit, and it is a copyright line for
Arm's *contributions to PyTorch* — not the Compute Library's MIT text. Those
texts have to be supplied by us.

The package therefore installs, under `/usr/share/doc/rr-libtorch/`:

| File | Source |
|---|---|
| `copyright` | generated, Debian format, one stanza per component |
| `LICENSE` `NOTICE` | copied from the build actually used |
| `legal/OpenBLAS.LICENSE` | this directory (arm64 only) |
| `legal/ArmComputeLibrary.LICENSE` | this directory (arm64 only) |
| `PROVENANCE` | generated — which tree, which origin, which files, sha256 |

### Internal distribution is still distribution

These packages are served only on the LAN, which lowers exposure but does not
remove the obligation. BSD-3-Clause and MIT attach to conveying binaries, and a
binary conveyed to a collaborator's machine, or onto a robot that leaves the
building, has been conveyed. The cost of complying is a few text files; the
cost of not is unbounded and arrives late.
