import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

globalThis.HTMLElement = class {}
const source = await readFile(new URL('../../app/javascript/elements/dielca_authorized_signer.js', import.meta.url), 'utf8')
const { default: Element } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function setup (fetchResult) {
  const handlers = new Map()
  const input = {
    value: 'person-demo', disabled: false,
    addEventListener: (name, fn) => handlers.set(name, fn),
    removeEventListener: (name) => handlers.delete(name)
  }
  let requests = 0
  let reloads = 0
  const form = {
    action: '/dielca/signing/authorized_signer',
    requestSubmit: () => { requests++ },
    addEventListener: (name, fn) => handlers.set(name, fn),
    removeEventListener: (name) => handlers.delete(name)
  }
  const status = { textContent: '' }
  const fallback = { hidden: false }
  globalThis.FormData = class extends Map {}
  globalThis.document = { querySelector: () => ({ content: 'csrf-demo' }) }
  globalThis.window = { location: { reload: () => { reloads++ } } }
  let sent
  globalThis.fetch = async (url, options) => { sent = { url, options }; return fetchResult }
  const element = new Element()
  element.querySelector = (selector) => ({ form, select: input, '[data-signer-status]': status, '[data-signer-fallback]': fallback })[selector]
  element.connectedCallback()
  // A real FormData captures the Rails _method and filtered signing_token.
  globalThis.FormData = class extends Map { constructor () { super([['_method', 'patch'], ['signing_token', 'demo-token']]) } }
  return { element, input, status, fallback, handlers, requests: () => requests, reloads: () => reloads, sent: () => sent }
}

test('selection automatically fills on the server and reloads the signing form', async () => {
  const state = setup({ ok: true, json: async () => ({ status: 'selected' }) })
  state.handlers.get('change')()
  assert.equal(state.requests(), 1)
  await state.handlers.get('submit')({ preventDefault () {} })
  assert.equal(state.sent().url, '/dielca/signing/authorized_signer')
  assert.equal(state.sent().options.body.get('authorized_signer_id'), 'person-demo')
  assert.equal(state.sent().options.body.get('_method'), 'patch')
  assert.equal(state.sent().options.headers['X-CSRF-Token'], 'csrf-demo')
  assert.equal(state.reloads(), 1)
  assert.equal(state.fallback.hidden, true)
  state.element.disconnectedCallback()
  assert.equal(state.handlers.size, 0)
})

test('failed selection leaves the form available for another choice', async () => {
  const state = setup({ ok: false, json: async () => ({ error: 'Not authorized' }) })
  await state.handlers.get('submit')({ preventDefault () {} })
  assert.equal(state.reloads(), 0)
  assert.equal(state.input.disabled, false)
  assert.match(state.status.textContent, /Vuelve a seleccionar/)
})
