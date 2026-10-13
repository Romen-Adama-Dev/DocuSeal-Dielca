import { identityError, normalizeIdentity } from '../dielca/spanish_identity'

export default class extends HTMLElement {
  connectedCallback () {
    this.abort = new AbortController()
    const options = { signal: this.abort.signal }
    const form = this.querySelector('form')
    const primary = form.querySelector('[name="primary_email"]')
    const identity = form.querySelector('[data-personal-id]')
    const status = form.querySelector('[data-confirmation-status]')
    const validate = () => {
      if (!identity) return
      identity.value = normalizeIdentity(identity.value)
      identity.setCustomValidity(identityError(identity.value))
    }
    if (identity) {
      identity.addEventListener('input', validate, options)
      validate()
    }
    form.querySelector('[data-change-email]').addEventListener('click', () => {
      primary.readOnly = false
      primary.focus()
    }, options)
    const extra = form.querySelector('[data-additional-emails]')
    const add = form.querySelector('[data-add-email]')
    add.addEventListener('click', () => {
      if (extra.children.length >= 4) return
      const input = document.createElement('input')
      input.name = 'additional_emails[]'
      input.type = 'email'
      input.maxLength = 254
      input.required = true
      input.className = 'input input-bordered w-full'
      input.setAttribute('aria-label', `Destinatario adicional ${extra.children.length + 1}`)
      extra.appendChild(input)
      add.disabled = extra.children.length === 4
      input.focus()
    }, options)
    form.addEventListener('submit', async (event) => {
      event.preventDefault()
      validate()
      if (identity && !identity.reportValidity()) return
      const choice = event.submitter?.value || 'confirm'
      if (choice !== 'none' && !form.reportValidity()) return
      const body = new FormData(form)
      body.set('copy_choice', choice)
      const buttons = [...form.querySelectorAll('button')]
      buttons.forEach((button) => { button.disabled = true })
      try {
        const response = await fetch(form.action, { method: 'POST', body, credentials: 'same-origin', headers: { Accept: 'application/json' } })
        const result = await response.json()
        if (!response.ok) throw new Error(result.error || 'No se pudo confirmar la copia.')
        window.location.reload()
      } catch (error) {
        status.textContent = error.message
        buttons.forEach((button) => { button.disabled = false })
        add.disabled = extra.children.length >= 4
      }
    }, options)
  }

  disconnectedCallback () {
    this.abort?.abort()
  }
}
