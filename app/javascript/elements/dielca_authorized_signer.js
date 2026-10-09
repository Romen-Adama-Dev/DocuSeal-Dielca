export default class extends HTMLElement {
  connectedCallback () {
    this.form = this.querySelector('form')
    this.select = this.querySelector('select')
    this.status = this.querySelector('[data-signer-status]')
    this.fallback = this.querySelector('[data-signer-fallback]')
    if (!this.form || !this.select) return
    this.onChange = () => { if (this.select.value) this.form.requestSubmit() }
    this.onSubmit = async (event) => {
      event.preventDefault()
      this.select.disabled = true
      this.status.textContent = 'Rellenando datos…'
      try {
        // Capture the selected ID even while the input is disabled.
        const body = new FormData(this.form)
        body.set('authorized_signer_id', this.select.value)
        const response = await fetch(this.form.action, {
          method: 'POST', body, credentials: 'same-origin',
          headers: { Accept: 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '' }
        })
        const result = await response.json()
        if (!response.ok) throw new Error(result.error || 'No se pudieron rellenar los datos.')
        window.location.reload()
      } catch (error) {
        this.status.textContent = 'No se pudieron rellenar los datos. Vuelve a seleccionar la persona.'
        this.select.disabled = false
      }
    }
    this.form.addEventListener('submit', this.onSubmit)
    this.select.addEventListener('change', this.onChange)
    this.fallback.hidden = true
  }

  disconnectedCallback () {
    this.form?.removeEventListener('submit', this.onSubmit)
    this.select?.removeEventListener('change', this.onChange)
  }
}
