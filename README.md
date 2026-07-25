# timescaledb-cnpg

TimescaleDB Community edition packaged as a [CloudNativePG](https://cloudnative-pg.io)
extension image, for mounting into a `Cluster` as a Kubernetes ImageVolume.

The image is `FROM scratch` and contains only TimescaleDB's own files:

```
/lib              shared libraries
/share/extension  control file and SQL scripts
```

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
  storage:
    size: 100Gi
```

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
```

Pin by digest in production. A tag can be moved; a digest cannot.

### Requirements

- PostgreSQL 18 or later, for the `extension_control_path` GUC
- CloudNativePG 1.27 or later
- Kubernetes 1.33 or later with the `ImageVolume` feature gate enabled
- `linux/amd64`

## Tags

`<timescaledb-version>-pg<postgresql-major>`, for example `2.28.3-pg18`, plus a
rolling `pg18`.

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

Read the [TimescaleDB release notes](https://github.com/timescale/timescaledb/releases)
before a bump, and have a backup. Upgrades are in place and intrusive.

## Building locally

```sh
docker buildx build --platform linux/amd64 -o type=local,dest=extension .
hack/verify.sh extension
```

`hack/verify.sh` mounts the tree into a stock CloudNativePG PostgreSQL image
the same way the operator mounts an ImageVolume, then asserts that the
Community features actually work: hypertables, columnstore compression and its
policy, a continuous aggregate and refresh policy, a retention policy, and
gap filling. CI runs the same script.

To build a different version:

```sh
docker buildx build --build-arg TSDB_VERSION=2.28.2 --platform linux/amd64 .
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
database-as-a-service. This image redistributes the binaries unmodified,
exactly as published in Timescale's own Debian packages. Read the license
before relying on it.
