# Extension images

OCI artifacts mounted alongside upstream application images with Kubernetes ImageVolumes.

| Extension | Build context | Published image |
| --- | --- | --- |
| TimescaleDB Community | [images/timescaledb](images/timescaledb) | `ghcr.io/inomotech-foss/timescaledb-cnpg` |
| TimescaleDB Toolkit | [images/timescaledb-toolkit](images/timescaledb-toolkit) | `ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit` |
| OpenBao TPM 2.0 | [images/openbao-tpm](images/openbao-tpm) | `ghcr.io/inomotech-foss/extension-images/openbao-tpm` |

[TimescaleDB usage and upgrades](images/timescaledb/README.md).

`build.yaml` plans changed images on `ubuntu-slim`, then builds and tests on
native amd64/arm64 runners. Published names and immutable tags survive repo renames.

To add an image: create `images/<name>/Dockerfile` and `image.json` with its
registry path, tag template (Dockerfile `ARG`s), and test suite. Add
`tests/<suite>/run.sh` and Renovate rules. Images sharing a suite are tested together.

Repository code: [Apache 2.0](LICENSE). Redistributed binaries retain their own licenses.
