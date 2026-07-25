# timescaledb-cnpg

TimescaleDB Community edition packaged as [CloudNativePG](https://cloudnative-pg.io)
extension images, for mounting into a `Cluster` as Kubernetes ImageVolumes.

Two images are published, because CloudNativePG mounts one image per entry in
`spec.postgresql.extensions` and the toolkit is a separate PostgreSQL extension:

| Extension | Image |
| --- | --- |
| `timescaledb` | `ghcr.io/inomotech-foss/timescaledb-cnpg` |
| `timescaledb_toolkit` | `ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit` |

Both are `FROM scratch` and contain only the extension's own files:

```
/lib              shared libraries
/share/extension  control file and SQL scripts
```

The toolkit image is optional. Take it when you want the hyperfunctions
(`counter_agg`, `state_agg`, `time_weight`, `approx_percentile`, …); TimescaleDB
itself does not need it.

## Why this exists

Neither existing option works:

- The [CloudNativePG extension images](https://github.com/cloudnative-pg/postgres-extensions-containers)
  ship TimescaleDB **Apache 2 edition**, which has no compression, no
  continuous aggregates, and no retention policies.
- The official `timescale/timescaledb-ha` image cannot be a CloudNativePG
  operand. It puts `PGDATA` at `/home/postgres/pgdata/data`, runs as uid 1000
  against CloudNativePG's uid 26, and bundles Patroni and pgBackRest, which
  duplicate the operator's own instance manager and backup plugin.

Packaging just the extension keeps the PostgreSQL operand image upstream, so
base image security updates need no rebuild here, and the PostgreSQL and
TimescaleDB versions upgrade independently.

## Usage

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
          reference: ghcr.io/inomotech-foss/timescaledb-cnpg:2.28.3-pg18
      - name: timescaledb_toolkit
        image:
          reference: ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit:1.23.0-pg18
  storage:
    size: 100Gi
```

Only `timescaledb` belongs in `shared_preload_libraries`. The toolkit is loaded
on demand and must not be preloaded.

`timescaledb.license: timescale` selects the Community edition. Setting it to
`apache` restricts the extension to Apache 2 features. It is a switch, not a
paid unlock.

Then create the extension in a database:

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

Pin by digest in production. A tag can be moved; a digest cannot.

### Requirements

- PostgreSQL 18 or later, for the `extension_control_path` GUC
- CloudNativePG 1.27 or later
- Kubernetes 1.33 or later with the `ImageVolume` feature gate enabled
  (enabled by default from 1.35), and containerd 2.1 or later
- `linux/amd64` or `linux/arm64`

## Tags

`<version>-pg<postgresql-major>`, for example `2.28.3-pg18` for TimescaleDB and
`1.23.0-pg18` for the toolkit. Each tag is a multi-architecture manifest list
covering `linux/amd64` and `linux/arm64`.

Only immutable tags are published. There is deliberately no rolling `pg18` tag:
changing a mounted extension image restarts PostgreSQL, so that must never
happen implicitly.

## Upgrades

The image keeps **every** TimescaleDB build the Debian package provides, not
only the version in the tag. PostgreSQL loads the shared library named by the
version recorded in the catalog, so an image carrying only the newest build
breaks every hypertable query between the pod restart and the extension
update:

```
ERROR:  could not access file "timescaledb-2.27.2": No such file or directory
```

Keeping the older builds makes the upgrade non-disruptive:

1. Bump the extension image reference. Changing an ImageVolume restarts the
   PostgreSQL pods, but queries keep working because the old library is still
   present.
2. Set `version` on the `Database` resource's extension entry, or leave it
   unset to take the new default. CloudNativePG runs `ALTER EXTENSION`.

The toolkit needs the same care for a different reason. Its package ships only
one library, named for its version (`timescaledb_toolkit-1.23.0.so`), with no
unversioned fallback at all. `TOOLKIT_VERSIONS` in `toolkit.Dockerfile` is
therefore a list, oldest first: every entry contributes its library, and the last
entry is the version the image is tagged with and the only one whose control file
and SQL scripts are installed. Keep the version a database is currently on in
that list until it has been updated.

Read the [TimescaleDB release notes](https://github.com/timescale/timescaledb/releases)
and the [toolkit release notes](https://github.com/timescale/timescaledb-toolkit/releases)
before a bump, and have a backup. Upgrades are in place and intrusive.

## Building locally

```sh
docker buildx build -o type=local,dest=extension .
docker buildx build -f toolkit.Dockerfile -o type=local,dest=toolkit .
hack/verify.sh extension toolkit
```

`hack/verify.sh` mounts the trees into a stock CloudNativePG PostgreSQL image
the same way the operator mounts an ImageVolume, then asserts that the features
actually work: hypertables, columnstore compression and its policy, a continuous
aggregate and refresh policy, a retention policy, and gap filling. Passing the
toolkit tree as a second argument additionally asserts that `counter_agg`
survives a counter reset, that `state_agg` reports the right time in state, and
that `time_weight` integrates to the right area. CI runs the same script, once
per architecture on a native runner.

The trees are architecture-specific and default to the host's architecture. To
check a tree built for another one, which needs QEMU:

```sh
docker buildx build --platform linux/arm64 -o type=local,dest=extension .
VERIFY_PLATFORM=linux/arm64 hack/verify.sh extension
```

To build a different version:

```sh
docker buildx build --build-arg TSDB_VERSION=2.28.2 .
docker buildx build -f toolkit.Dockerfile --build-arg TOOLKIT_VERSIONS="1.21.0 1.22.0" .
```

The build fails rather than silently drifting if that version has no package
for the base image's Debian release, or if the resulting control file does not
advertise it.

## Licensing

The files in this repository are Apache 2.0 licensed. See `LICENSE`.

The **image contents are not**. TimescaleDB Community edition is licensed
under the [Timescale License](https://github.com/timescale/timescaledb/blob/main/tsl/LICENSE-TIMESCALE),
which permits free use for internal business purposes and distribution of
unmodified binaries, but prohibits offering TimescaleDB as a
database-as-a-service. TimescaleDB Toolkit is licensed under the same Timescale
License in its entirety. Both images redistribute the binaries unmodified,
exactly as published in Timescale's own Debian packages. Read the license
before relying on it.
