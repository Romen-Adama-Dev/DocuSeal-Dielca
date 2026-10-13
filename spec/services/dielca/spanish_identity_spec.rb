# frozen_string_literal: true

RSpec.describe Dielca::SpanishIdentity do
  cases = JSON.parse(Rails.root.join('spec/fixtures/dielca_identity_cases.json').read)
  cases.each do |example|
    it "classifies the fictitious identity #{example['value'].inspect}" do
      expect(described_class.type(example['value'])).to eq(example['type']&.to_sym)
      if example['type']
        expect(described_class.normalize(example['value'])).to eq(example['normalized'] || example['value'])
      end
      expected_error = if example['type'] == 'cif'
                         described_class::COMPANY_ERROR
                       elsif example['type'].nil?
                         described_class::INVALID_ERROR
                       end
      expect(described_class.error(example['value'])).to eq(expected_error)
    end
  end
end
