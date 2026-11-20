# TimescaleDB and Toolkit

TimescaleDB Community edition and TimescaleDB Toolkit as extension images for
[CloudNativePG](https://cloudnative-pg.io/). The images mount into a stock
CloudNativePG PostgreSQL container through Kubernetes ImageVolumes.

| Extension | Image |
| --- | --- |
| `timescaledb` | `ghcr.io/inomotech-foss/timescaledb-cnpg` |
| `timescaledb_toolkit` | `ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit` |

Toolkit is optional. It provides hyperfunctions such as `counter_agg`,
`state_agg`, and `time_weight`.

## Requirements

- PostgreSQL 18, matching the image's `pg18` tag
- CloudNativePG 1.27 or later
- Kubernetes 1.33 or later with `ImageVolume` enabled (on by default from 1.35)
- A runtime with image volume support, such as containerd 2.1 or later
- `linux/amd64` or `linux/arm64`

## Usage

Add the extension images to a `Cluster`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: timescaledb
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18-standard-trixie
  postgresql:
    shared_preload_libraries:
      - timescaledb
    parameters:
      timescaledb.license: timescale
    extensions:
      - name: timescaledb
        image:
          reference: ghcr.io/inomotech-foss/timescaledb-cnpg:2.32.0-pg18
      - name: timescaledb_toolkit
        image:
          reference: ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit:1.27.0-pg18
  storage:
    size: 100Gi
```

Preload `timescaledb` only. Toolkit loads on demand. The `timescale` license
setting enables the Community features, including compression, continuous
aggregates, and retention policies.

Create the extensions in each database through a `Database` resource. The
owner role (`app` below) must already exist:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: metrics
spec:
  name: metrics
  owner: app
  cluster:
    name: timescaledb
  extensions:
    - name: timescaledb
      ensure: present
    - name: timescaledb_toolkit
      ensure: present
```

Omit the Toolkit entries if you do not need it. Use image digests for production
deployments.

## Images and upgrades

Tags use `<extension-version>-pg<postgresql-major>`. Each tag covers both supported
architectures. CI leaves published tags unchanged; there are no rolling tags.

Both images use `FROM scratch` and contain shared libraries in `/lib` and
extension control files and SQL scripts in `/share/extension`. PostgreSQL stays
in the upstream CloudNativePG image and can be updated separately.

To upgrade an extension:

1. Read the [TimescaleDB release notes](https://github.com/timescale/timescaledb/releases)
   or [Toolkit release notes](https://github.com/timescale/timescaledb-toolkit/releases)
   and back up the database.
2. Update its image reference in the `Cluster`. This restarts the PostgreSQL pods.
3. Set the target `version` on its `Database.spec.extensions` entry.
   CloudNativePG applies the SQL upgrade with `ALTER EXTENSION`.

The database catalog still refers to the old extension library between steps 2
and 3. The TimescaleDB image retains every library included in its Debian
package. The Toolkit image collects libraries from `TOOLKIT_MIN_VERSION` through
`TOOLKIT_VERSION`; only the target release supplies control files and SQL.
Check that your installed version is included before changing images. Raise the
Toolkit minimum only after all databases have upgraded beyond it. Keeping the
old libraries does not remove the pod restart or guarantee a zero-downtime
upgrade.

## Development

From the repository root, build and verify the extensions with Docker Buildx:

```sh
docker buildx build -o type=local,dest=extension images/timescaledb
docker buildx build -o type=local,dest=toolkit images/timescaledb-toolkit
tests/timescaledb/verify.sh extension toolkit
```

Verification loads both extensions into stock CloudNativePG PostgreSQL. It checks
compressed chunk reads, continuous aggregates, policy creation, gap filling, and
Toolkit aggregate results. CI runs on native amd64 and arm64 runners.

CI also exports the previous published images to `previous/timescaledb` and
`previous/toolkit`, then runs:

```sh
tests/timescaledb/verify-upgrade.sh extension toolkit previous/timescaledb previous/toolkit
```

This creates data with the previous extensions, restarts PostgreSQL with the new
extension trees, checks queries before `ALTER EXTENSION`, and checks them again
after the SQL upgrades and another restart. It uses a temporary Docker volume
that is removed on exit. Previous image references are pinned in
[the workflow](../../.github/workflows/timescaledb.yaml).

Use `--platform` for cross-platform builds and set the same `VERIFY_PLATFORM`
when verifying them. Running another architecture requires emulation support.
Override `TSDB_VERSION` or `TOOLKIT_VERSION` with `--build-arg` to build other
releases. Builds require a matching Debian package for the base image's release.
Toolkit versions use the extension version, without GitHub tag suffixes such as
`+p2`.

Renovate tracks extension releases and the base image. CI validates its
configuration, tests release version extraction, and checks that the README's
image references match the Dockerfiles.

## License

Repository code is [Apache 2.0 licensed](../../LICENSE). The images redistribute
unmodified TimescaleDB and Toolkit binaries under the
[Timescale License](https://github.com/timescale/timescaledb/blob/main/tsl/LICENSE-TIMESCALE).
Review that license for the terms that apply to your use and redistribution.
