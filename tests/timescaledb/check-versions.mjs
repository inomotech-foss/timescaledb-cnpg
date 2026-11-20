import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const config = JSON.parse(readFileSync('renovate.json', 'utf8'));
const manager = config.customManagers.find(
  (entry) => entry.depNameTemplate === 'timescale/timescaledb-toolkit',
);
const extract = new RegExp(manager.extractVersionTemplate);
for (const [tag, expected] of [
  ['1.26.0', '1.26.0'],
  ['1.27.0+p2', '1.27.0'],
  ['v1.27.0+p2', '1.27.0'],
  ['1.27.0+p10', '1.27.0'],
  ['1.28.0', '1.28.0'],
  ['1.28.0-rc.1', undefined],
  ['1.28.0-rc.1+p2', undefined],
  ['1.27.0+unknown', undefined],
]) {
  assert.equal(extract.exec(tag)?.groups.version, expected, tag);
}

const timescaledb = readFileSync('images/timescaledb/Dockerfile', 'utf8');
const toolkit = readFileSync('images/timescaledb-toolkit/Dockerfile', 'utf8');
const readme = readFileSync('images/timescaledb/README.md', 'utf8');
const arg = (file, name) => {
  const match = file.match(new RegExp(`^ARG ${name}=(\\S+)$`, 'm'));
  assert.ok(match, `missing ${name}`);
  return match[1];
};
const pgMajor = arg(timescaledb, 'PG_MAJOR');
assert.equal(arg(toolkit, 'PG_MAJOR'), pgMajor, 'PostgreSQL majors differ');
assert.equal(arg(toolkit, 'BASE_IMAGE'), arg(timescaledb, 'BASE_IMAGE'), 'base images differ');
for (const [image, version] of [
  ['ghcr.io/inomotech-foss/timescaledb-cnpg', arg(timescaledb, 'TSDB_VERSION')],
  ['ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit', arg(toolkit, 'TOOLKIT_VERSION')],
]) {
  assert.ok(readme.includes(`reference: ${image}:${version}-pg${pgMajor}`),
    `update README example for ${image}`);
  const dependency = config.customManagers.find(
    (entry) => entry.depNameTemplate === (image.endsWith('/toolkit')
      ? 'timescale/timescaledb-toolkit' : 'timescale/timescaledb'),
  );
  assert.ok(dependency.managerFilePatterns.includes('/^images/timescaledb/README\\.md$/'),
    `Renovate must track README for ${image}`);
  const captured = dependency.matchStrings
    .map((pattern) => new RegExp(pattern).exec(readme)?.groups.currentValue)
    .filter((value) => value !== undefined);
  assert.deepEqual(captured, [version], `Renovate must extract the README version for ${image}`);
}
console.log('Release version extraction, shared build arguments, and README examples verified');
