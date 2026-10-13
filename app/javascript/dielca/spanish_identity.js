const letters = 'TRWAGMYFPDXBNJZSQVHLCKE'
const companyLetters = 'JABCDEFGHI'

export function normalizeIdentity (value) {
  return String(value ?? '').toUpperCase().replace(/[\s./_-]/g, '').replace(/^ES/, '')
}

export function identityType (input) {
  const value = normalizeIdentity(input)
  if (/^\d{8}[A-Z]$/.test(value)) return letters[Number(value.slice(0, 8)) % 23] === value.at(-1) ? 'dni' : null
  if (/^[XYZ]\d{7}[A-Z]$/.test(value)) {
    const number = 'XYZ'.indexOf(value[0]) + value.slice(1, 8)
    return letters[Number(number) % 23] === value.at(-1) ? 'nie' : null
  }
  if (/^[KLM]\d{7}[A-Z]$/.test(value)) return letters[Number(value.slice(1, 8)) % 23] === value.at(-1) ? 'nif' : null
  if (/^[ABCDEFGHJNPQRSUVW]\d{7}[A-J0-9]$/.test(value)) {
    const sum = [...value.slice(1, 8)].reduce((sum, digit, index) => {
      const doubled = Number(digit) * 2
      return sum + (index % 2 === 0 ? Math.floor(doubled / 10) + doubled % 10 : Number(digit))
    }, 0)
    const control = (10 - sum % 10) % 10
    const allowed = 'NPQRSW'.includes(value[0]) ? [companyLetters[control]] : ('ABEH'.includes(value[0]) ? [String(control)] : [String(control), companyLetters[control]])
    return allowed.includes(value.at(-1)) ? 'cif' : null
  }
  return null
}

export function identityError (value) {
  const type = identityType(value)
  if (type === 'cif') return 'Es un CIF de empresa; indique su DNI o NIE'
  return ['dni', 'nie', 'nif'].includes(type) ? '' : 'DNI/NIE inválido; compruebe el número y la letra'
}
