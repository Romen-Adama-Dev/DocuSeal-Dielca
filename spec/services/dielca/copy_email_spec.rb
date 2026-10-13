# frozen_string_literal: true

RSpec.describe Dielca::CopyEmail do
  let(:record) do
    double(customer_data: { 'email' => 'cliente@example.invalid' }, selected_signer_id: 'person',
           authorized_signers: [{ 'id' => 'person', 'email' => 'autorizado@example.invalid' }])
  end
  let(:submitter) { double(metadata: {}) }

  before { allow(submitter).to receive(:metadata=) { |data| allow(submitter).to receive(:metadata).and_return(data) } }

  it 'prefers the selected authorized person and falls back to the customer' do
    expect(described_class.proposed(record)).to eq('autorizado@example.invalid')
    allow(record).to receive(:authorized_signers).and_return([])
    expect(described_class.proposed(record)).to eq('cliente@example.invalid')
  end

  it 'requires explicit false to omit the copy' do
    expect { described_class.confirm!(record, submitter, copy_choice: 'none') }
      .to raise_error(Submitters::SubmitValues::ValidationError)
    allow(record).to receive(:customer_data).and_return('copy_email_required' => false)
    described_class.confirm!(record, submitter, copy_choice: 'none')
    expect { described_class.validate!(record, submitter) }.not_to raise_error
  end

  it 'normalizes and stores changed address and up to five recipients' do
    extras = (1..4).map { |i| "extra#{i}@example.invalid" }
    described_class.confirm!(record, submitter, primary_email: ' NUEVO@example.invalid ', additional_emails: extras)
    data = submitter.metadata.fetch('dielca_copy_email')
    expect(data).to include('changed' => true, 'primary' => 'nuevo@example.invalid', 'additional' => extras,
                            'status' => 'pending', 'confirmed' => true)
    expect(data['recipients'].size).to eq(5)
    expect { described_class.validate!(record, submitter) }.not_to raise_error
  end

  it 'records an unchanged address and deduplicates recipients' do
    described_class.confirm!(record, submitter, primary_email: 'autorizado@example.invalid',
                                                additional_emails: ['autorizado@example.invalid'])
    expect(submitter.metadata['dielca_copy_email']).to include('changed' => false,
                                                               'recipients' => ['autorizado@example.invalid'])
  end

  it 'rejects six recipients, malformed addresses and header injection' do
    expect do
      described_class.confirm!(record, submitter, primary_email: 'a@example.invalid',
                                                  additional_emails: ['b@example.invalid'] * 5)
    end
      .to raise_error(Submitters::SubmitValues::ValidationError)
    ['bad', ['a@example.invalid'], "a@example.invalid\r\nBcc: x@example.invalid"].each do |email|
      expect { described_class.confirm!(record, submitter, primary_email: email) }
        .to raise_error(Submitters::SubmitValues::ValidationError)
    end
  end

  it 'blocks signing without a confirmed choice' do
    expect { described_class.validate!(record, submitter) }.to raise_error(Submitters::SubmitValues::ValidationError)
  end
end
