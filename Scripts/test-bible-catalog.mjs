import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const source = readFileSync(new URL('../Sources/Domain/BibleModels.swift', import.meta.url), 'utf8');
const catalog = source.split('static let publicDomain:')[1].split('static let languagePopularityOrder')[0];
const ids = [...catalog.matchAll(/\.init\(id: "([^"]+)"/g)].map(m => m[1]).sort();
assert.equal(ids.length, new Set(ids).size, 'Duplicate catalog ID');
const migration = readFileSync(new URL('../supabase/migrations/202611030003_public_domain_bible_release.sql', import.meta.url), 'utf8');
const arrays = [...migration.matchAll(/array\[([^\]]+)\]/g)];
assert.equal(arrays.length, 3, 'Expected normalization, constraint and RPC allowlists');
for (const array of arrays) {
  const sqlIDs = [...array[1].matchAll(/'([^']+)'/g)].map(m => m[1]).sort();
  assert.deepEqual(sqlIDs, ids, 'Client and database catalogs differ');
}
const fingerprints = new Map([...source.matchAll(/"([a-z0-9-]+)": "([a-f0-9]{64})"/g)].map(m => [m[1],m[2]]));
const evidence = JSON.parse(readFileSync(new URL('../docs/bible-release-evidence/provider-contract.json', import.meta.url), 'utf8'));
assert.deepEqual(evidence.results.map(r => r.version).sort(), ids, 'Every offered version needs evidence');
assert.deepEqual([...fingerprints.keys()].sort(), ids, 'Every offered version needs a reviewed credit');
for (const row of evidence.results) {
  assert.equal(row.verified, true);
  assert.equal(row.returned_version, row.version);
  assert.equal(row.has_credit, true);
  assert.equal(row.credit_matches_catalog, true);
  const hash = createHash('sha256').update(row.catalog_notice.trim()).digest('hex');
  assert.equal(fingerprints.get(row.version), hash, `Rights notice differs for ${row.version}`);
}
const provenance = JSON.parse(readFileSync(new URL('../docs/bible-release-evidence/source-metadata.json', import.meta.url), 'utf8'));
for (const row of provenance.results.filter(r => ids.includes(r.version))) {
  assert.equal(row.metadata.license, 'public-domain', `Text license differs for ${row.version}`);
  assert.equal(row.metadata.sourceVerified, true, `Unverified dataset offered: ${row.version}`);
  assert.ok(row.metadata.sourceUrl, `Missing source for ${row.version}`);
}
console.log(`Bible catalog, database allowlists and reviewed provider credits agree for ${ids.length} versions.`);
