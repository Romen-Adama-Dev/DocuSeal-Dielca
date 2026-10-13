# frozen_string_literal: true

module Dielca
  module SpanishIdentity
    LETTERS = 'TRWAGMYFPDXBNJZSQVHLCKE'
    COMPANY_LETTERS = 'JABCDEFGHI'
    COMPANY_ERROR = 'Es un CIF de empresa; indique su DNI o NIE'
    INVALID_ERROR = 'DNI/NIE inválido; compruebe el número y la letra'

    module_function

    def normalize(value)
      value.to_s.upcase.gsub(%r{[[:space:]./_-]}, '').delete_prefix('ES')
    end

    def type(value)
      value = normalize(value)
      case value
      when /\A\d{8}[A-Z]\z/
        :dni if LETTERS[value[0, 8].to_i % 23] == value[-1]
      when /\A[XYZ]\d{7}[A-Z]\z/
        number = value[0].tr('XYZ', '012') + value[1, 7]
        :nie if LETTERS[number.to_i % 23] == value[-1]
      when /\A[KLM]\d{7}[A-Z]\z/
        :nif if LETTERS[value[1, 7].to_i % 23] == value[-1]
      when /\A[ABCDEFGHJNPQRSUVW]\d{7}[A-J0-9]\z/
        :cif if valid_company?(value)
      end
    end

    def valid_company?(value)
      sum = value[1, 7].chars.map(&:to_i).each_with_index.sum do |digit, index|
        index.even? ? (digit * 2).div(10) + ((digit * 2) % 10) : digit
      end
      control = (10 - (sum % 10)) % 10
      allowed = if 'NPQRSW'.include?(value[0])
                  [COMPANY_LETTERS[control]]
                elsif 'ABEH'.include?(value[0])
                  [control.to_s]
                else
                  [control.to_s, COMPANY_LETTERS[control]]
                end
      allowed.include?(value[-1])
    end

    def error(value)
      kind = type(value)
      return COMPANY_ERROR if kind == :cif

      INVALID_ERROR unless %i[dni nie nif].include?(kind)
    end
  end
end
