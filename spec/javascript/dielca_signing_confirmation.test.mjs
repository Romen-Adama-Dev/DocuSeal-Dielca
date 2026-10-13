import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const identity = await readFile(new URL('../../app/javascript/dielca/spanish_identity.js', import.meta.url), 'utf8')
const identityURL = `data:text/javascript;base64,${Buffer.from(identity).toString('base64')}`
const source = (await readFile(new URL('../../app/javascript/elements/dielca_signing_confirmation.js', import.meta.url), 'utf8'))
  .replace('../dielca/spanish_identity', identityURL)
globalThis.HTMLElement = class {}
const { default: Element } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function setup (documentValue = '12345678Z') {
  const handlers = {}
  function control (key) {
    return { value: '', disabled: false, focus () {}, setAttribute () {},
      addEventListener (event, fn) { handlers[`${key}:${event}`] = fn } }
  }
  const id = { ...control('id'), value: documentValue, error: '',
    setCustomValidity (message) { this.error = message }, reportValidity () { return !this.error } }
  const primary = { ...control('primary'), readOnly: true }
  const extra = { children: [], appendChild (input) { this.children.push(input) } }
  const add = control('add')
  const change = control('change')
  const status = { textContent: '' }
  const form = { ...control('form'), action: '/dielca/signing/confirmation', reportValidity: () => true,
    querySelector (selector) {
      return { '[name="primary_email"]': primary, '[data-personal-id]': id,
        '[data-confirmation-status]': status, '[data-change-email]': change,
        '[data-additional-emails]': extra, '[data-add-email]': add }[selector]
    }, querySelectorAll: () => [add, change] }
  let calls = 0
  let reloads = 0
  globalThis.document = { createElement: () => control('new') }
  globalThis.FormData = class extends Map { constructor () { super() } }
  globalThis.window = { location: { reload: () => { reloads++ } } }
  globalThis.fetch = async () => { calls++; return { ok: true, json: async () => ({ status: 'confirmed' }) } }
  const element = new Element()
  element.querySelector = () => form
  element.connectedCallback()
  return { id, primary, extra, add, handlers, calls: () => calls, reloads: () => reloads }
}

test('invalid personal ID blocks confirmation and company CIF has the requested error', async () => {
  for (const value of ['kdfjkdds', '', '12345678A', 'B12345674']) {
    const state = setup(value)
    await state.handlers['form:submit']({ preventDefault () {} })
    assert.equal(state.calls(), 0)
    if (value === 'B12345674') assert.equal(state.id.error, 'Es un CIF de empresa; indique su DNI o NIE')
  }
})

test('normalizes ID, allows changing email, and limits additions to four', async () => {
  const state = setup(' es 12.345/678-z_ ')
  assert.equal(state.id.value, '12345678Z')
  state.handlers['change:click']()
  assert.equal(state.primary.readOnly, false)
  for (let i = 0; i < 5; i++) state.handlers['add:click']()
  assert.equal(state.extra.children.length, 4)
  assert.equal(state.add.disabled, true)
  await state.handlers['form:submit']({ preventDefault () {}, submitter: { value: 'confirm' } })
  assert.equal(state.calls(), 1)
  assert.equal(state.reloads(), 1)
})
