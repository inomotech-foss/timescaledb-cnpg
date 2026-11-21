# TimescaleDB and Toolkit

Community binaries for CloudNativePG PostgreSQL 18. Requires CNPG 1.27+, Kubernetes
ImageVolumes, and containerd 2.1+ (or another supporting runtime). Both images
support amd64 and arm64.

In the CNPG `Cluster`:

```yaml
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18-standard-trixie
  postgresql:
    shared_preload_libraries: [timescaledb]
    parameters:
      timescaledb.license: timescale
    extensions:
      - name: timescaledb
        image:
          reference: ghcr.io/inomotech-foss/timescaledb-cnpg:2.32.0-pg18
      - name: timescaledb_toolkit
        image:
          reference: ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit:1.27.0-pg18
```

Toolkit is optional; never preload it. Create the extensions through
`Database.spec.extensions`. Pin image digests in production.

Tags are `<version>-pg<major>`, immutable, with no rolling tags. Images contain
`/lib` and `/share/extension`; PostgreSQL stays in the upstream image.

For upgrades, back up first, change the image, then set the target version in
`Database.spec.extensions`. The image change restarts pods. The old library must
remain available until the SQL upgrade finishes. TimescaleDB retains package
libraries; Toolkit retains versions from `TOOLKIT_MIN_VERSION` through
`TOOLKIT_VERSION`. Raise that minimum only after consumers have upgraded.

Build and verify from the repository root:

```sh
docker buildx build -o type=local,dest=extension/timescaledb images/timescaledb
docker buildx build -o type=local,dest=extension/timescaledb-toolkit images/timescaledb-toolkit
tests/timescaledb/run.sh
```

The suite checks Community features, Toolkit results, and upgrades from the
previous published images. Cross-architecture runs need emulation and matching
`--platform`/`VERIFY_PLATFORM`. Override Dockerfile version arguments with
`--build-arg`; omit GitHub Toolkit tag suffixes such as `+p2`.

Binaries use the [Timescale License](https://github.com/timescale/timescaledb/blob/main/tsl/LICENSE-TIMESCALE).
