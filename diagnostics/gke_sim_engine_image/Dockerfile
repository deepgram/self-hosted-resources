# Linker-level model of the Deepgram self-hosted Engine image, used by CI to
# exercise dg_gke_libcuda_smoke.sh without Deepgram registry credentials.
# This is NOT a Deepgram image. It reproduces only the property under test:
#
#   Engine images since release-260611 register their bundled libraries via
#   /etc/ld.so.conf.d + ldconfig at build time and set no LD_LIBRARY_PATH,
#   while linking against libcuda.so.1, which is provided by the host at
#   runtime (on GKE: bind-mounted at /usr/local/nvidia/lib64 with no NVIDIA
#   container toolkit to make it visible to the dynamic linker).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*

# Stand-in for a bundled library (libtorch/gstreamer/openh264): non-standard
# directory, registered via ld.so.conf.d + ldconfig like the real image.
RUN mkdir -p /libtorch/lib && \
    printf 'int internal_fn(void){return 7;}\n' > /tmp/internal.c && \
    gcc -shared -fPIC -Wl,-soname,libinternal.so.1 -o /libtorch/lib/libinternal.so.1 /tmp/internal.c && \
    ln -s libinternal.so.1 /libtorch/lib/libinternal.so

# Stand-in for the NVIDIA driver's libcuda.so.1: built here only so the binary
# can link against it. It is left at /out (on no linker search path) so CI can
# extract it and bind-mount it at runtime, exactly how GKE exposes the driver.
RUN mkdir -p /out && \
    printf 'int cuda_fn(void){return 42;}\n' > /tmp/cuda.c && \
    gcc -shared -fPIC -Wl,-soname,libcuda.so.1 -o /out/libcuda.so.1 /tmp/cuda.c

# Stand-in for the impeller binary: needs BOTH the bundled lib and libcuda.so.1.
RUN printf '#include <stdio.h>\nint internal_fn(void); int cuda_fn(void);\nint main(void){printf("engine up: internal=%%d cuda=%%d\\n", internal_fn(), cuda_fn()); return 0;}\n' > /tmp/main.c && \
    gcc -o /bin/impeller /tmp/main.c -L/libtorch/lib -linternal /out/libcuda.so.1

# Replicate the refactor: register ONLY the bundled libs; no LD_LIBRARY_PATH.
RUN echo "/libtorch/lib" > /etc/ld.so.conf.d/impeller.conf && ldconfig

ENTRYPOINT ["/bin/impeller"]
