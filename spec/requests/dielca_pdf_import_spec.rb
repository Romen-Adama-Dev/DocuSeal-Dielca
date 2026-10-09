# frozen_string_literal: true

RSpec.describe 'DIELCA original BC PDF API' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:layout) { create(:template, account:, author:, only_field_types: %w[text signature]) }
  let(:request_id) { '00000000-0000-4000-8000-000000000001' }
  let(:bytes) { Rails.root.join('spec/fixtures/sample-document.pdf').binread }
  let(:headers) { { 'X-Auth-Token' => author.access_token.token } }

  around do |example|
    keys = %w[DIELCA_BC_USER_ID DIELCA_BC_LAYOUT_TEMPLATE_ID]
    previous = keys.to_h { |key| [key, ENV[key]] }
    ENV['DIELCA_BC_USER_ID'] = author.id.to_s
    ENV['DIELCA_BC_LAYOUT_TEMPLATE_ID'] = layout.id.to_s
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    fields = layout.fields
    name = fields.find { |f| f['type'] == 'text' }
    name['name'] = 'Nombre'
    id_field = name.deep_dup.merge('uuid' => SecureRandom.uuid, 'name' => 'DNI/NIF')
    id_field['areas'] = id_field['areas'].map { |a| a.merge('y' => 0.20) }
    signature = fields.find { |f| f['type'] == 'signature' }
    signature['name'] = 'Firma'
    layout.update!(fields: [name, id_field, signature])
  end

  def import(overrides = {}, auth: headers, **changes)
    file = Tempfile.new(['bc-example', '.pdf'])
    file.binmode
    file.write(bytes)
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, 'application/pdf')
    post '/api/dielca/v1/submissions_from_pdf', headers: auth, params: {
      request_id:, layout_template_id: layout.id.to_s,
      pdf: upload, pdf_sha256: Digest::SHA256.hexdigest(bytes),
      document_name: 'Pedido ficticio', order_number: 'PED-DEMO', customer_name: 'Cliente ficticio',
      signer_name: '', send_email: 'false', send_sms: 'false'
    }.merge(overrides).merge(changes)
  ensure
    file&.close!
  end

  it 'advertises idempotent PDF import with the allowed layout' do
    get '/api/dielca/v1/pdf_import_capabilities', headers:, params: { layout_template_id: layout.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('idempotent' => true, 'mode' => 'bc_pdf', 'version' => 1)
  end

  it 'keeps the original bytes, creates required editable fields and never sends invitations' do
    expect(Submissions).not_to receive(:send_signature_requests)
    import
    expect(response).to have_http_status(:created)
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    expect(record.submission.template.documents.first.download).to eq(bytes)
    expect(record.submitter.completed_at).to be_nil
    expect(record.submitter.email).to be_blank
    expect(record.submitter.phone).to be_blank
    expect(record.submitter.preferences).to include('send_email' => false, 'send_sms' => false)
    fields = record.submission.template.fields
    expect(fields.map { |f| f['name'] }).to eq(['Nombre', 'DNI/NIF', 'Firma'])
    expect(fields).to all(include('required' => true, 'readonly' => false))
    expect(record.submitter.values).to be_empty
    expect(record.submission.template.shared_link).to be(false)
    expect(record.submission.template.template_accesses.pluck(:user_id)).to eq([author.id])
  end

  it 'returns the same submission and signer on replay' do
    import
    first = response.parsed_body.slice('submission_id', 'submitter_id')
    expect { import }.not_to change(Submission, :count)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.slice('submission_id', 'submitter_id')).to eq(first)
  end

  it 'rejects reuse of a request with a different signer' do
    import
    expect { import(signer_name: 'Otra persona ficticia') }.not_to change(Submission, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('IDEMPOTENCY_CONFLICT')
  end

  it 'rejects an incorrect hash before creating an import' do
    expect { import(pdf_sha256: '0' * 64) }.not_to change(Submission, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('error', 'code')).to eq('PDF_HASH_MISMATCH')
  end

  it 'does not accept autocompletion' do
    import(completed: 'true')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('error', 'code')).to eq('COMPLETED_FORBIDDEN')
  end

  it 'does not accept email or SMS dispatch' do
    import(send_email: 'true')
    expect(response.parsed_body.dig('error', 'code')).to eq('NOTIFICATIONS_FORBIDDEN')
    import(send_sms: 'true')
    expect(response.parsed_body.dig('error', 'code')).to eq('NOTIFICATIONS_FORBIDDEN')
  end

  it 'requires token authentication, even with a signed-in session' do
    sign_in author
    import({}, auth: {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a token from another account' do
    other = create(:user)
    import({}, auth: { 'X-Auth-Token' => other.access_token.token })
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects a layout outside the allowlist' do
    import(layout_template_id: '0')
    expect(response).to have_http_status(:forbidden)
  end

  it 'is disabled until the server is configured' do
    ENV.delete('DIELCA_BC_USER_ID')
    import
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig('error', 'code')).to eq('IMPORT_DISABLED')
  end

  it 'rolls back records and deletes new storage objects after a rendering failure' do
    allow_any_instance_of(Dielca::PdfSubmission).to receive(:preview!).and_raise('private details')
    expect { import }.not_to change(Submission, :count)
    expect(Dielca::PdfImport.where(account:, request_id:)).to be_empty
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.to_json).not_to include('private details')
    allow_any_instance_of(Dielca::PdfSubmission).to receive(:preview!).and_call_original
    import
    expect(response).to have_http_status(:created)
  end

  it 'preloads an authorized name as an editable value' do
    import(signer_name: 'Persona ficticia')
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    expect(record.submitter.values[record.name_field_uuid]).to eq('Persona ficticia')
  end

  context 'with more than sixteen pages' do
    let(:bytes) do
      document = HexaPDF::Document.new
      17.times { document.pages.add }
      StringIO.new.tap { |io| document.write(io) }.string
    end

    it 'renders the last page and places fields on it' do
      import
      expect(response).to have_http_status(:created)
      template = Dielca::PdfImport.find_by!(account:, request_id:).submission.template
      document = template.documents.first
      expect(document.preview_images.blobs.pluck(:filename)).to include('16.jpg')
      expect(template.fields.flat_map { |f| f['areas'] }.pluck('page')).to all(eq(16))
      expect(document.download).to eq(bytes)
    end
  end

  context 'with an encrypted PDF' do
    let(:bytes) do
      document = HexaPDF::Document.new
      document.pages.add
      document.encrypt(user_password: 'test-only', owner_password: 'test-only-owner')
      StringIO.new.tap { |io| document.write(io) }.string
    end

    it 'rejects it without modifying records' do
      expect { import }.not_to change(Submission, :count)
      expect(response.parsed_body.dig('error', 'code')).to eq('PDF_ENCRYPTED')
    end
  end

  context 'with a broken PDF' do
    let(:bytes) { '%PDF-1.7 invalid content' }

    it 'rejects it without creating a submission' do
      expect { import }.not_to change(Submission, :count)
      expect(response.parsed_body.dig('error', 'code')).to eq('PDF_INVALID')
    end
  end
end
