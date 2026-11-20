# Extension images

OCI images containing extensions and their runtime dependencies, for mounting
alongside upstream application images with Kubernetes ImageVolumes. This
repository builds and tests the artifacts; deployment configuration belongs in
the consuming infrastructure repositories.

| Extension | Source | Published image |
| --- | --- | --- |
| TimescaleDB Community | [images/timescaledb](images/timescaledb) | `ghcr.io/inomotech-foss/timescaledb-cnpg` |
| TimescaleDB Toolkit | [images/timescaledb-toolkit](images/timescaledb-toolkit) | `ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit` |

See the [TimescaleDB and Toolkit guide](images/timescaledb/README.md) for usage,
compatibility requirements, upgrades, and local verification.

## Repository layout

```text
images/<name>/       Dockerfile, build context, and extension-specific docs
tests/<family>/      Compatibility and upgrade tests against upstream images
ci/                  Shared publishing safeguards
.github/workflows/   Build and release workflows scoped to each image family
```

TimescaleDB and Toolkit retain their joint compatibility and upgrade tests
because they are used together. Their extension versions and published tags
remain independent. Unrelated extensions get their own tests and workflow;
changes to those images do not trigger the TimescaleDB workflow.

## Adding an extension

1. Add its build context under `images/<name>/`. The published artifact should
   contain only the extension and necessary dependencies, with no secrets or
   mutable application state.
2. Document the supported upstream application image, OS/ABI, and architectures.
   Build and test against that upstream image rather than relying only on file
   presence or successful linking.
3. Add compatibility tests under `tests/<family>/` and a workflow with path
   filters for that family and any shared build or publishing code it uses.
4. Choose an explicit image destination and an immutable tag scheme encoding
   the compatibility constraints. Do not derive published image names from
   `github.repository`: renaming this repository must not change image names.
5. Configure dependency updates for the new paths in `renovate.json`. Preserve
   publishing safeguards, native architecture tests, and build provenance.

## Published names

The TimescaleDB package names above are intentionally preserved for existing
consumers, even if the source repository is renamed. CI publishes them only
from the `inomotech-foss` organization; forks can build and test without
publishing to those destinations. New extension images can use different
package names and release versions without renaming the existing packages.

## License

Repository code is [Apache 2.0 licensed](LICENSE). Each extension's documentation
describes the license of the binaries redistributed in its images.
