# frozen_string_literal: true

RSpec.describe 'DIELCA original BC PDF API' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:layout) { create(:template, account:, author:, only_field_types: %w[text signature]) }
  let(:request_id) { '00000000-0000-4000-8000-000000000001' }
  let(:bytes) { Rails.root.join('spec/fixtures/sample-document.pdf').binread }
  let(:customer_data) do
    { id: '00000000-0000-4000-8000-000000000003', number: 'CLI-DEMO', name: 'Cliente ficticio',
      vat_registration_no: 'NIF empresa ficticio', address: 'Calle ficticia 1', city: 'Ciudad ficticia',
      post_code: '00000', address2: '', county: '', country_code: 'ES' }
  end
  let(:signers) do
    [{ id: '00000000-0000-4000-8000-000000000004', contact_number: 'DEMO-1',
       name: 'Persona ficticia Uno', job_title: 'Cargo ficticio', id_document_no: '12345678Z' },
     { id: '00000000-0000-4000-8000-000000000005', contact_number: 'DEMO-2',
       name: 'Persona ficticia Dos', job_title: 'Cargo ficticio', id_document_no: 'X1234567L' }]
  end
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
      customer: customer_data.to_json, authorized_signers: signers.to_json,
      signer_name: '', send_email: 'false', send_sms: 'false', copy_email_required: 'false'
    }.merge(overrides).merge(changes)
  ensure
    file&.close!
  end

  it 'persists BC 0.3 customer and authorized identity types' do
    import(customer: customer_data.merge(id_type: 'CIF').to_json,
           authorized_signers: signers.map { |s| s.merge(id_document_type: 'NIE') }.to_json)
    expect(response).to have_http_status(:created)
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    expect(record.customer_data['id_type']).to eq('CIF')
    expect(record.authorized_signers.pluck('id_document_type')).to eq(%w[NIE NIE])
  end

  it 'rejects unknown identity types before creating a submission' do
    expect { import(customer: customer_data.merge(id_type: 'Other').to_json) }.not_to change(Submission, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('error', 'code')).to eq('CUSTOMER_DATA_INVALID')
  end

  it 'replays legacy snapshots without optional types' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    expect(record.customer_data).not_to have_key('id_type')
    expect(record.authorized_signers).to all(satisfy { |s| !s.key?('id_document_type') })
    expect { import }.not_to change(Submission, :count)
    expect(response).to have_http_status(:created)
  end

  it 'advertises idempotent PDF import with the allowed layout' do
    get '/api/dielca/v1/pdf_import_capabilities', headers:, params: { layout_template_id: layout.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('idempotent' => true, 'mode' => 'bc_pdf', 'version' => 1, 'free_signing' => true)
  end

  it 'keeps the original bytes, creates readonly identity fields and never sends invitations' do
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
    expect(fields).to all(include('required' => true))
    expect(fields.select { |f| f['type'] == 'text' }).to all(include('readonly' => true))
    expect(fields.find { |f| f['type'] == 'signature' }['readonly']).to be(false)
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

  it 'rejects reuse of a request with a different authorization snapshot' do
    import
    expect { import(authorized_signers: [signers.first.merge(name: 'Otra persona ficticia')].to_json) }.not_to change(Submission, :count)
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
    expect_any_instance_of(ActiveStorage::Blob).to receive(:delete).once.and_call_original
    allow_any_instance_of(Dielca::PdfSubmission).to receive(:preview!).and_raise('private details')
    expect { import }.not_to change(Submission, :count)
    expect(Dielca::PdfImport.where(account:, request_id:)).to be_empty
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.to_json).not_to include('private details')
    allow_any_instance_of(Dielca::PdfSubmission).to receive(:preview!).and_call_original
    import
    expect(response).to have_http_status(:created)
  end

  it 'preserves committed originals when indexing fails and recovers them on replay' do
    allow(SearchEntries).to receive(:enqueue_reindex).and_raise(ActiveRecord::RecordNotUnique)
    import
    expect(response).to have_http_status(:service_unavailable)
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    expect(record.submission.template.documents.first.download).to eq(bytes)
    allow(SearchEntries).to receive(:enqueue_reindex).and_call_original
    expect { import }.not_to change(Submission, :count)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['submission_id']).to eq(record.submission_id)
  end

  def select_person(record, person_id = signers.first[:id])
    patch '/dielca/signing/authorized_signer', params: {
      signing_token: record.submitter.slug, authorized_signer_id: person_id
    }, headers: { 'Accept' => 'application/json' }
  end

  def confirm_signing(record, **options)
    post '/dielca/signing/confirmation', params: {
      signing_token: record.submitter.slug, signer_name: 'Persona presente ficticia',
      personal_id: ' es 12.345/678-z_ ', copy_choice: 'none'
    }.merge(options), headers: { 'Accept' => 'application/json' }
  end

  it 'fills name and identity document from the selected authorized person' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    expect(response).to have_http_status(:ok)
    record.reload
    expect(record.selected_signer_id).to eq(signers.first[:id])
    expect(record.submitter.reload.values[record.name_field_uuid]).to eq(signers.first[:name])
    expect(record.submitter.values[record.id_field_uuid]).to eq(signers.first[:id_document_no])
    expect(record.submitter.name).to eq(signers.first[:name])
    expect(record.submitter.completed_at).to be_nil
  end

  it 'displays customer information and the authorized-person dropdown before signing' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    get submit_form_path(slug: record.submitter.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Datos del cliente', 'Cliente ficticio', 'NIF empresa ficticio')
    expect(response.body).to include('Persona autorizada que firma', 'Persona ficticia Uno', 'Persona ficticia Dos')
    expect(response.body).not_to include('<submission-form')
  end

  it 'shows signing only after selection and keeps the personal DNI separate from customer NIF' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    get submit_form_path(slug: record.submitter.slug)
    expect(response.body).not_to include('<submission-form')
    expect(response.body).to include('Es correcto', 'Cambiar')
    confirm_signing(record)
    expect(response).to have_http_status(:ok)
    get submit_form_path(slug: record.submitter.slug)
    expect(response.body).to include('<submission-form', '12345678Z', 'NIF empresa ficticio')
    expect(response.body).to include('data-reuse-signature="false"')
  end

  it 'does not allow selection of a person outside this customer snapshot' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record, SecureRandom.uuid)
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.reload.selected_signer_id).to be_nil
  end

  it 'clears an unfinished signature when switching to another person' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    confirm_signing(record)
    signature_uuid = record.submission.template.fields.find { |f| f['type'] == 'signature' }['uuid']
    record.submitter.reload.update!(values: record.submitter.values.merge(signature_uuid => 'old-drawing'))
    select_person(record, signers.last[:id])
    expect(response).to have_http_status(:ok)
    expect(record.submitter.reload.values).not_to have_key(signature_uuid)
    expect(record.submitter.values[record.name_field_uuid]).to eq(signers.last[:name])
  end

  it 'refuses to change the signer of an already completed form' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    record.submitter.reload.update!(completed_at: Time.current)
    select_person(record, signers.last[:id])
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.reload.selected_signer_id).to eq(signers.first[:id])
  end

  it 'rejects forged manual identity instead of a dropdown selection' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    put submit_form_path(slug: record.submitter.slug), params: {
      completed: 'true', values: { record.name_field_uuid => 'Inventado', record.id_field_uuid => 'Inventado' }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.submitter.reload.completed_at).to be_nil
  end

  it 'completes the form after selection without resubmitting readonly identity fields' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    confirm_signing(record)
    signature_uuid = record.submission.template.fields.find { |f| f['type'] == 'signature' }['uuid']
    put submit_form_path(slug: record.submitter.slug), params: {
      completed: 'true', values: { signature_uuid => 'test-signature' }
    }
    expect(response).to have_http_status(:ok)
    expect(record.submitter.reload.completed_at).to be_present
    expect(record.submitter.name).to eq(signers.first[:name])
    expect(record.submitter.values[record.id_field_uuid]).to eq(signers.first[:id_document_no])
    expect(record.submission.reload.completed_at).to be_present
  end

  context 'when BC returns no authorized people' do
    let(:signers) { [] }

    it 'filters typed identity values from Rails parameter logs' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      params = { 'values' => { 'name-uuid' => 'Persona ficticia', 'id-uuid' => 'ID personal ficticio' } }
      expect(filter.filter(params)['values']).to eq('[FILTERED]')
    end

    it 'creates blank editable required identity fields and shows no dropdown' do
      import(signer_mode: 'free', signer_name: 'Texto que no debe precargarse')
      expect(response).to have_http_status(:created)
      record = Dielca::PdfImport.find_by!(account:, request_id:)
      expect(record.signer_mode).to eq('free')
      expect(record.submitter.values).to be_empty
      fields = record.submission.template.fields.select { |f| f['type'] == 'text' }
      expect(fields).to all(include('readonly' => false, 'required' => true))
      get submit_form_path(slug: record.submitter.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('<submission-form')
      expect(response.body).to include('Datos del cliente', 'DNI/NIE personal', 'data-personal-id')
      confirm_signing(record)
      expect(response).to have_http_status(:ok)
      get submit_form_path(slug: record.submitter.slug)
      expect(response.body).to include('<submission-form', 'dielca_personal_identity')
      expect(response.body).not_to include('<dielca-authorized-signer', 'Persona autorizada que firma')
    end

    it 'completes with the name and personal DNI typed by the signer' do
      import(signer_mode: 'free')
      record = Dielca::PdfImport.find_by!(account:, request_id:)
      confirm_signing(record)
      signature_uuid = record.submission.template.fields.find { |f| f['type'] == 'signature' }['uuid']
      put submit_form_path(slug: record.submitter.slug), params: {
        completed: 'true', values: { record.name_field_uuid => 'Persona presente ficticia',
                                    record.id_field_uuid => ' es 12.345/678-z_ ', signature_uuid => 'test-signature' }
      }
      expect(response).to have_http_status(:ok)
      expect(record.submitter.reload.completed_at).to be_present
      expect(record.submitter.name).to eq('Persona presente ficticia')
      expect(record.submitter.values[record.id_field_uuid]).to eq('12345678Z')
      expect(record.submitter.values[record.id_field_uuid]).not_to eq(customer_data[:vat_registration_no])
    end

    it 'rejects completion without a personal DNI' do
      import(signer_mode: 'free')
      record = Dielca::PdfImport.find_by!(account:, request_id:)
      put submit_form_path(slug: record.submitter.slug), params: {
        completed: 'true', values: { record.name_field_uuid => 'Persona ficticia' }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(record.submitter.reload.completed_at).to be_nil
      expect(record.submitter.values[record.id_field_uuid]).to be_blank
    end

    %w[12345678A X1234567A kdfjkdds B12345674 P1234567D].each do |document|
      it "rejects invalid or company identity #{document} on the server" do
        import(signer_mode: 'free')
        record = Dielca::PdfImport.find_by!(account:, request_id:)
        put submit_form_path(slug: record.submitter.slug), params: {
          completed: 'true', values: { record.name_field_uuid => 'Persona ficticia', record.id_field_uuid => document }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(record.submitter.reload.completed_at).to be_nil
        if document.start_with?('B', 'P')
          expect(response.parsed_body['error']).to eq('Es un CIF de empresa; indique su DNI o NIE')
        end
      end
    end

    it 'never replaces a free import when an authorized list is later supplied' do
      import(signer_mode: 'free')
      record = Dielca::PdfImport.find_by!(account:, request_id:)
      person = { id: SecureRandom.uuid, contact_number: 'DEMO-NEW', name: 'Persona ficticia',
                 job_title: '', id_document_no: 'ID ficticio' }
      expect { import(authorized_signers: [person].to_json, signer_mode: 'authorized') }.not_to change(Submission, :count)
      expect(response).to have_http_status(:conflict)
      expect(record.reload.signer_mode).to eq('free')
      expect(record.authorized_signers).to be_empty
    end

    it 'rejects an inconsistent explicit authorized mode' do
      import(signer_mode: 'authorized')
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('error', 'code')).to eq('SIGNER_MODE_INVALID')
    end
  end

  it 'returns the selected identity only to the technical API user' do
    import
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    get "/api/dielca/v1/pdf_imports/#{request_id}", headers: headers
    expect(response.parsed_body).to include('selected_signer_id' => signers.first[:id],
                                           'signer_name' => signers.first[:name],
                                           'signer_id_document_no' => signers.first[:id_document_no])
  end

  it 'uses customerEmail when the customer snapshot has no email and proposes the authorized email first' do
    import(customer: customer_data.merge(email: '').to_json, customerEmail: 'cliente@example.invalid',
           authorized_signers: [signers.first.merge(email: 'persona@example.invalid')].to_json,
           copy_email_required: 'true')
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    expect(record.customer_data['email']).to eq('cliente@example.invalid')
    select_person(record)
    get submit_form_path(slug: record.submitter.slug)
    expect(response.body).to include('persona@example.invalid', 'Es correcto', 'Cambiar')
    expect(response.body).not_to include('Sin copia por correo', '<submission-form')
    confirm_signing(record, copy_choice: 'confirm', primary_email: 'persona@example.invalid')
    expect(response).to have_http_status(:ok)
    expect(record.submitter.reload.metadata['dielca_copy_email']).to include('changed' => false)
  end

  it 'rejects an invalid authorized document before offering signature capture' do
    import(authorized_signers: [signers.first.merge(id_document_no: 'kdfjkdds')].to_json)
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.reload.selected_signer_id).to be_nil
  end

  it 'requires confirmation even when the selected identity is valid' do
    import(copy_email_required: 'true', customerEmail: 'cliente@example.invalid')
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    select_person(record)
    signature_uuid = record.submission.template.fields.find { |f| f['type'] == 'signature' }['uuid']
    put submit_form_path(slug: record.submitter.slug), params: { values: { signature_uuid => 'test-signature' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.submitter.reload.values).not_to have_key(signature_uuid)
    confirm_signing(record)
    expect(response).to have_http_status(:unprocessable_content)
    confirm_signing(record, copy_choice: 'confirm', primary_email: 'nuevo@example.invalid',
                            additional_emails: ['extra@example.invalid'])
    expect(response).to have_http_status(:ok)
    get "/api/dielca/v1/pdf_imports/#{request_id}", headers: headers
    expect(response.parsed_body['copy_email']).to include('changed' => true,
      'recipients' => ['nuevo@example.invalid', 'extra@example.invalid'])
  end

  it 'rejects signature uploads before identity and email confirmation' do
    import(signer_mode: 'free', authorized_signers: '[]')
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    post "/s/#{record.submitter.slug}/upload", params: { type: 'signature' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to include('antes de firmar')
    confirm_signing(record, personal_id: 'kdfjkdds')
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.submitter.reload.values).to be_empty
  end

  it 'rejects a forged personal ID sent together with an unfinished signature' do
    import(signer_mode: 'free', authorized_signers: '[]')
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    confirm_signing(record)
    signature_uuid = record.submission.template.fields.find { |field| field['type'] == 'signature' }['uuid']
    put submit_form_path(slug: record.submitter.slug), params: {
      values: { signature_uuid => 'test-signature', record.id_field_uuid => 'kdfjkdds' }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.submitter.reload.values).not_to have_key(signature_uuid)
    expect(record.submitter.values[record.id_field_uuid]).to eq('12345678Z')
  end

  it 'rejects confirmation for an unknown signing capability' do
    post '/dielca/signing/confirmation', params: { signing_token: 'unknown-fictitious-token' },
                                         headers: { 'Accept' => 'application/json' }
    expect(response).to have_http_status(:forbidden)
  end

  [1, 3].each do |pages|
    context "with #{pages} fictitious A5 landscape pages" do
      let(:bytes) do
        document = HexaPDF::Document.new
        pages.times { document.pages.add([0, 0, 595.28, 419.53]) }
        StringIO.new.tap { |io| document.write(io) }.string
      end

      it 'uses the report profile on the last page and fits both texts on one line' do
        import(signer_mode: 'free', authorized_signers: '[]', reportId: '50000', documentType: 'PostedShipment',
               document_number: 'ALB-DEMO')
        expect(response).to have_http_status(:created)
        record = Dielca::PdfImport.find_by!(account:, request_id:)
        confirm_signing(record, signer_name: 'Persona ficticia de nombre largo para comprobar la caja')
        expect(response).to have_http_status(:ok)
        signature = record.submission.template.fields.find { |field| field['type'] == 'signature' }
        image = Vips::Image.black(180, 70).new_from_image([255, 255, 255])
        image = image.draw_line([0, 0, 0], 10, 50, 45, 15).draw_line([0, 0, 0], 45, 15, 30, 60)
        png = image.draw_line([0, 0, 0], 30, 60, 165, 20).pngsave_buffer
        record.submitter.attachments.attach(io: StringIO.new(png), filename: 'fictitious-signature.png',
                                            content_type: 'image/png')
        drawing = record.submitter.attachments.last
        put submit_form_path(slug: record.submitter.slug), params: {
          completed: 'true', values: { signature['uuid'] => drawing.uuid }
        }
        expect(response).to have_http_status(:ok)
        generated = Submissions::GenerateResultAttachments.generate_pdfs(record.submitter.reload).values.first
        expect(generated.pages.count).to eq(pages)
        expect(generated.pages[pages - 1][:Resources][:XObject]).to be_present
        generated.pages.to_a[0...-1].each { |page| expect(page[:Resources][:XObject]).to be_blank }
        fields = record.submission.reload.template_fields
        expect(fields.flat_map { |field| field['areas'] }.pluck('page')).to all(eq(pages - 1))
        pdf = HexaPDF::Document.new
        font = pdf.fonts.add('Helvetica', custom_encoding: true)
        fields.select { |field| field['type'] == 'text' }.each do |field|
          area = field['areas'].first
          expect(Dielca::SingleLineIdentity.fits?(record.submitter.reload.values[field['uuid']], font,
            field.dig('preferences', 'font_size'), area['w'] * 595.28 - 1, area['h'] * 419.53)).to be(true)
        end
      end
    end
  end

  { 'A5' => [595.28, 419.53], 'A4' => [595.28, 841.89] }.each do |paper, size|
    [1, 3].each do |pages|
      context "with a #{pages}-page invoice ending in #{paper}" do
        let(:bytes) do
          document = HexaPDF::Document.new
          other = paper == 'A5' ? [595.28, 841.89] : [595.28, 419.53]
          (pages - 1).times { document.pages.add([0, 0, *other]) }
          document.pages.add([0, 0, *size])
          StringIO.new.tap { |io| document.write(io) }.string
        end

        %w[free authorized].each do |mode|
          it "imports in #{mode} mode using the approved #{paper == 'A5' ? 'shipment' : 'order'} positions" do
            params = { signer_mode: mode, reportId: '50001', documentType: 'PostedInvoice',
                       document_number: 'FAC-DEMO' }
            params[:authorized_signers] = '[]' if mode == 'free'
            import(**params)
            expect(response).to have_http_status(:created)
            record = Dielca::PdfImport.find_by!(account:, request_id:)
            expect(record.signer_mode).to eq(mode)
            expect(record.submitter.metadata).to include('report_id' => '50001', 'document_type' => 'PostedInvoice')
            fields = record.submission.template.fields
            expect(fields.flat_map { |field| field['areas'] }.pluck('page')).to all(eq(pages - 1))
            signature = fields.find { |field| field['name'] == 'Firma' }['areas'].sole
            expect(signature['x']).to be_within(0.000001).of(paper == 'A5' ? 0.202 : 0.34)
            expect(signature['y']).to be_within(0.000001).of(paper == 'A5' ? 0.7707 : 0.815)
            expect(fields.select { |field| field['type'] == 'text' }.pluck('readonly')).to all(eq(mode == 'authorized'))
            expect { import(**params) }.not_to change(Submission, :count)
            expect(response).to have_http_status(:created)
            expect(response.parsed_body['submission_id']).to eq(record.submission_id)
          end
        end
      end
    end
  end

  context 'with an invoice in an unsupported paper size' do
    let(:bytes) do
      document = HexaPDF::Document.new
      document.pages.add([0, 0, 612, 792])
      StringIO.new.tap { |io| document.write(io) }.string
    end

    it 'rejects the import before creating a submission' do
      expect { import(reportId: '50001', documentType: 'PostedInvoice') }.not_to change(Submission, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('error', 'code')).to eq('REPORT_LAYOUT_NOT_CONFIGURED')
      expect(Dielca::PdfImport.find_by(account:, request_id:)).to be_nil
    end
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

RSpec.describe 'DIELCA BC customer identity display', type: :view do
  it 'distinguishes companies and natural persons without editable customer fields' do
    customer = { 'name' => 'Cliente ficticio', 'vat_registration_no' => 'Documento ficticio' }
    { 'CIF' => 'Empresa', 'DNI' => 'Persona física', 'NIE' => 'Persona física',
      'NIF' => 'Persona física', 'None' => 'Tipo de identificación no indicado' }.each do |type, label|
      record = double(customer_data: customer.merge('id_type' => type), authorized_signers: [],
                      selected_signer_id: nil, free_signing?: true, name_field_uuid: 'name', id_field_uuid: 'id')
      render partial: 'dielca/bc_signing_details', locals: { record:, submitter: double(values: {}, metadata: {}, slug: 'fictitious') }
      expect(rendered).to include('Cliente ficticio', label)
      expect(rendered).not_to include('name="customer', 'name="id_type')
    end
  end
end
