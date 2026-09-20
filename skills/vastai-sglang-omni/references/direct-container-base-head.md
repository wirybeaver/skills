# Base-vs-Head service benchmark in a direct container

Use this reference when a comparative benchmark runs prebuilt application
images directly as provider containers. The worked example is the
[ARK-ASR encoder CUDA Graph full SeedTTS-EN benchmark](https://gist.github.com/wirybeaver/079e2faf1e95e314ec91994511f4ae95).

## Freeze the experiment contract

Record before renting a GPU:

- exact Base and Head commits;
- the common parent-image digest and build recipe;
- the two application-image digests required by the parent skill's image-parity
  contract;
- the single Head-only feature switch, if any;
- model and dataset identifiers and immutable revisions;
- input fingerprint, expected sample count, correctness gates, and metrics;
- concurrency grid, cache modes, repetition ownership, aggregation, and outer
  execution order;
- instance cleanup policy.

Completion criterion: a reviewer can identify every intended Base-vs-Head
difference and reproduce every matrix cell from the contract.

## Build the two-image set

Create clean detached worktrees for Base and Head. Build both with the same
Dockerfile and digest-pinned parent, changing only the source revision and
revision label. Push both images and resolve their immutable registry digests.

Record a source marker inside each image and smoke both application
entrypoints. For a Head feature controlled by a runtime option, enable that
option only in the Head server command. Base still comes from the Base image;
running the Head image without the option is a different experiment.

Completion criterion: both digests resolve, each container reports its expected
source revision, and both pass the same CUDA and application smoke checks.

## Control order on one GPU

Use the same rented GPU for all outer blocks when the provider can reliably
switch direct-container images:

```text
Order A / position 1: Base
Order A / position 2: Head
Order B / position 1: Head
Order B / position 2: Base

Global sequence: Base -> Head -> Head -> Base
```

This balances first/second-position effects while avoiding an unnecessary
image switch between the two adjacent Head blocks. Record and compare the GPU
UUID after every recycle. Keep model, dataset, server defaults, benchmark
command, power state, and prepared inputs fixed.

Completion criterion: every result is labeled with order, position, revision,
image digest, source commit, and GPU UUID.

## Define cache-state sessions

Keep application warmup separate from the measured cache state.

### Initially empty embedding cache

For each concurrency, use independent sessions:

```text
fresh server
  -> one discarded warmup over inputs disjoint from the measured corpus
  -> one measured full-corpus pass
  -> stop server
```

Repeat the session the declared number of times. A warmup drawn from the
measured corpus changes this into a partially warm-cache experiment.

### Warm embedding cache

For each concurrency:

```text
fresh server
  -> one unmeasured full-corpus prime
  -> measured full-corpus repeats on the same server
  -> stop server
```

The prime and measured repeats share one server. Restarting between them clears
the cache state being measured.

Let the application own repeats when it emits per-repeat correctness and
latency metrics; configure the outer runner for one invocation.

Completion criterion: each session manifest identifies cache state,
concurrency, warmup/prime inputs, repeat index, server lifecycle, and artifact
directory.

Derive expected counts before execution. For the worked example's four outer
blocks, four concurrency levels, three empty-cache sessions, and three
warm-cache measured repeats:

```text
server sessions = 4 * 4 * (3 empty + 1 warm) = 64
measured passes = 4 * 4 * (3 empty + 3 warm) = 96
discarded disjoint warmups = 4 * 4 * 3 = 48
unmeasured full-corpus primes = 4 * 4 = 16
```

## Switch images without losing evidence

Finish and collect one outer block before replacing the direct container.
Have `$vastai` select and perform the provider update/recycle; then let
`$vastai-gpu-runtime` revalidate the resulting container. After
each switch:

1. verify the provider's active image digest;
2. verify the in-container source marker and expected files;
3. verify the GPU UUID;
4. rerun CUDA and application smoke checks;
5. restore scripts, model/data preparation, and caches if container-local
   storage was replaced.

Start measurements only after all five checks pass.

## Validate every measured pass

Preserve all application-emitted metrics, including:

- correctness such as WER and evaluated/skipped counts;
- throughput;
- mean, median, P95, and P99 latency;
- real-time factor or domain-specific metrics;
- resource and utilization samples;
- raw request or prediction output.

Add mechanism-specific gates when the optimization claims a mechanism. For
example, a startup-only CUDA Graph implementation should record the expected
capture count and zero capture/replay failures for every Head server.

Require one input fingerprint and one GPU UUID across the comparison. Preserve
per-repeat values; aggregate only after validating the complete artifact set.
Report the arithmetic or statistical method and signed Head-vs-Base deltas.

Completion criterion: expected sessions and measured passes are complete,
correctness gates pass, mechanism gates pass, and every result traces to raw
artifacts and immutable provenance.

## Collect, verify, then destroy

Before each image recycle, transfer the completed block and verify its SHA-256
manifest locally. After all blocks are collected:

1. verify every block manifest;
2. validate expected session, pass, request, and raw-artifact counts;
3. destroy the rented instance;
4. verify the instance is absent from the provider list;
5. aggregate and prepare the results for review or reporting.

Publishing or filing results externally is a separate action and requires the
confirmation required by the governing workflow.

Verified collection precedes destruction. Complete validation precedes
aggregation.
