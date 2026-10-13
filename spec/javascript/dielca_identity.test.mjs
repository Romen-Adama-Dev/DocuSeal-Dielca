import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = await readFile(new URL('../../app/javascript/dielca/spanish_identity.js', import.meta.url), 'utf8')
const { normalizeIdentity, identityType, identityError } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const cases = JSON.parse(await readFile(new URL('../fixtures/dielca_identity_cases.json', import.meta.url), 'utf8'))

for (const example of cases) {
  test(`checks fictitious identity ${JSON.stringify(example.value)}`, () => {
    assert.equal(identityType(example.value), example.type)
    if (example.type) assert.equal(normalizeIdentity(example.value), example.normalized || example.value)
    assert.equal(identityError(example.value), example.type === 'cif' ? 'Es un CIF de empresa; indique su DNI o NIE' : (example.type ? '' : 'DNI/NIE inválido; compruebe el número y la letra'))
  })
}
