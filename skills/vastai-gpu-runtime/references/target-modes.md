# Vast.ai GPU target modes

Read this reference when selecting the execution environment. Use the official
`$vastai` skill for offer search, instance/template/volume operations, SSH
endpoint resolution, billing, and destroy/stop commands.

## Provider image with SSH bootstrap

Use a compatible provider CUDA/PyTorch image without replacing its outer image.
After connecting, read `/etc/vast-agents-guide.md` when present, upload the
pinned source, and use the direct-container preflight. Its absence is normal in
custom images.

Record the provider-reported image, in-container OS/CUDA/Python identity,
source revision, install commands, GPU UUID, and application smoke result.
Nested Docker is not part of this mode.

## Prebuilt application image

Build and publish an immutable application image before provisioning. The Vast
instance/template must actually launch that digest; do not combine an unrelated
provider template with an assumed image override.

For Base-vs-Head on one rented GPU, collect the completed arm before switching
images. Treat container-local storage as replaceable. After the provider
recreates/recycles the container, resolve the current SSH endpoint and verify:

- provider-reported active image digest;
- in-container source revision marker;
- expected application files or version output;
- unchanged GPU UUID.

Provider/container disagreement is a failed image gate, not benchmark evidence.

## Docker host

Select a VM-capable target and boot the approved VM image. A working guest
driver and Docker daemon do not prove NVIDIA Container Toolkit readiness.
Require the Docker-host preflight to validate `nvidia-ctk` or
`nvidia-container-cli`, containerized `nvidia-smi`, and the application CUDA
smoke.

If only the toolkit layer is missing on an exclusive disposable VM, use the
previewed narrow repair from the runtime skill and rerun the complete preflight.
Kernel-driver installation and provider-host repair remain outside scope.

## Connection and terminal invariants

Resolve the current SSH endpoint for every fresh/recycled container. Use bounded
connection attempts and a per-run known-hosts file; do not reuse endpoints from
prior instances.

Every provider poll has a deadline and terminal branches. Collect artifacts
before destroying a disposable instance, redact credentials, then use
`$vastai` to perform and verify the approved stop/destroy action. The runtime is
complete only when the created instance is terminal/non-billable and absent
from the active listing, or when an existing target has no owned runtime left.
