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

  it 'preserves BC warehouse and routing metadata and refuses scope changes on replay' do
    scope = { location_code: 'SITE TEST', channel: 'Delivery', route_id: 'ROUTE-TEST',
              route_description: 'Ruta ficticia', requested_by: 'ACTOR-TEST' }
    import(**scope)
    expect(response).to have_http_status(:created)
    record = Dielca::PdfImport.find_by!(account:, request_id:)
    expect(record.submitter.metadata).to include(scope.stringify_keys)
    expect { import(**scope) }.not_to change(Submission, :count)
    expect(response).to have_http_status(:created)
    expect { import(**scope.merge(location_code: 'OTHER SITE')) }.not_to change(Submission, :count)
    expect(response).to have_http_status(:conflict)
    expect(record.submitter.reload.metadata['location_code']).to eq('SITE TEST')
  end

  it 'keeps empty scope metadata compatible with legacy imports' do
    import
    id = response.parsed_body['submission_id']
    import(location_code: '', channel: '', route_id: '', route_description: '', requested_by: '')
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['submission_id']).to eq(id)
  end

  it 'rejects malformed scope metadata before creating any submission' do
    [{ location_code: ['SITE'] }, { channel: 'forged' }, { route_id: "bad\ncode" }].each do |scope|
      expect { import(**scope) }.not_to change(Submission, :count)
      expect(response.parsed_body.dig('error', 'code')).to eq('BC_SCOPE_METADATA_INVALID')
    end
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

  [1, 3].product([false, true]).each do |pages, edited|
    context "with #{pages} fictitious A5 landscape pages #{edited ? "edited" : "legacy"}" do
      let(:bytes) do
        document = HexaPDF::Document.new
        pages.times do
          page = document.pages.add([0, 0, 595.28, 419.53])
          if edited
            canvas = page.canvas.font('Helvetica', size: 6)
            canvas.rectangle(28, 44.5, 151, 43).stroke
            canvas.text('FIRMA DEL CLIENTE - RECIBI CONFORME', at: [30, 80])
            canvas.text('Nombre:', at: [32, 69])
            canvas.text('DNI:', at: [32, 58])
            canvas.text('Fecha:', at: [32, 48])
          end
        end
        StringIO.new.tap { |io| document.write(io) }.string
      end

      it 'uses the report profile on the last page and fits both texts on one line' do
        import(signer_mode: 'free', authorized_signers: '[]', reportId: '50000', documentType: 'PostedShipment',
               document_number: 'ALB-DEMO')
        expect(response).to have_http_status(:created)
        record = Dielca::PdfImport.find_by!(account:, request_id:)
        expected_profile = edited ? '50000_A5_customer' : '50000_A5'
        expect(record.submitter.metadata['report_layout_id']).to eq(expected_profile)
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
        timestamp = record.submission.template.fields.find do |field|
          field.dig('preferences', 'dielca_signing_timestamp')
        end
        time_format = edited ? '%d/%m/%Y %H:%M:%S' : "%d/%m/%Y\n%H:%M:%S"
        expect(record.submitter.reload.values[timestamp['uuid']])
          .to eq(record.submitter.completed_at.in_time_zone('Atlantic/Canary').strftime(time_format))
        generated = Submissions::GenerateResultAttachments.generate_pdfs(record.submitter.reload).values.first
        expect(generated.pages.count).to eq(pages)
        expect(generated.pages[pages - 1][:Resources][:XObject].each.count).to eq(edited ? 1 : 2)
        generated.pages.to_a[0...-1].each { |page| expect(page[:Resources][:XObject]).to be_blank }
        if edited && pages == 1 && ENV['DIELCA_TEST_PREVIEW'] == 'true'
          generated.write('/tmp/dielca-A5-edited-demo.pdf')
        end
        fields = record.submission.reload.template_fields
        expect(fields.flat_map { |field| field['areas'] }.pluck('page')).to all(eq(pages - 1))
        pdf = HexaPDF::Document.new
        font = pdf.fonts.add('Helvetica', custom_encoding: true)
        fields.select { |field| field.dig('preferences', 'dielca_single_line') }.each do |field|
          area = field['areas'].first
          expect(Dielca::SingleLineIdentity.fits?(record.submitter.reload.values[field['uuid']], font,
            field.dig('preferences', 'font_size'), area['w'] * 595.28 - 1, area['h'] * 419.53)).to be(true)
        end
      end
    end
  end

  [
    ['50000', false], ['50001', false], ['50002', false], ['50000', true], ['50002', true]
  ].product([1, 3]).each do |(report, stacked), pages|
    context "with a #{pages}-page A4 report #{report} #{stacked ? "stacked" : "inline"} using the latest placement" do
      let(:bytes) do
        pdf = HexaPDF::Document.new
        pages.times do
          page = pdf.pages.add([0, 0, 595.28, 841.89])
          canvas = page.canvas.font('Helvetica', size: 12)
          canvas.text('DOCUMENTO FICTICIO - REVISION DE FIRMA', at: [40, 800])
          canvas.font('Helvetica', size: 7).text('Fecha documento: 01/01/2026', at: [40, 730])
          if stacked
            canvas.font('Helvetica', size: 7)
            if report == '50000'
              canvas.rectangle(28, 74.89, 363, 53).stroke
              canvas.text('RECIBÍ CONFORME', at: [33.17, 116])
              canvas.text('Nombre / cargo:', at: [33.17, 104])
              canvas.text('DNI:', at: [33.17, 92])
              canvas.text('Fecha:', at: [33.17, 80])
            else
              canvas.rectangle(210.5, 74.89, 179.9, 94.8).stroke
              canvas.text('CONFORME CLIENTE (FIRMA Y SELLO)', at: [216, 160])
              canvas.text('Nombre:', at: [216, 110])
              canvas.text('DNI:', at: [216, 96])
              canvas.text('Fecha:', at: [216, 82])
            end
          elsif report == '50000'
            canvas.rectangle(28, 74.89, 363, 17).stroke
            canvas.font('Helvetica', size: 6)
            canvas.text('RECIBI CONFORME', at: [32, 81])
            canvas.text('Nombre / cargo:', at: [104, 81])
            canvas.text('DNI:', at: [207.85, 81])
            canvas.text('Fecha:', at: [262.73, 81])
            canvas.text('Firma:', at: [312, 81])
          elsif report == '50001'
            canvas.rectangle(28, 88, 195, 94).stroke
            canvas.font('Helvetica', size: 7).text('RECIBI CONFORME', at: [32, 174])
          else
            canvas.rectangle(210.5, 77.5, 179.9, 94.8).stroke
            canvas.font('Helvetica', size: 7)
            canvas.text('CONFORME CLIENTE (FIRMA Y SELLO)', at: [216, 164])
            canvas.text('Nombre: ____________  DNI: __________  Fecha:', at: [216, 82])
          end
        end
        StringIO.new.tap { |io| pdf.write(io) }.string
      end

      it 'stamps server time in the date area and persists it for subsequent PDF generation' do
        document_type = case report
                        when '50000' then 'PostedShipment'
                        when '50001' then 'PostedInvoice'
                        else 'SalesOrder'
                        end
        import(signer_mode: 'free', authorized_signers: '[]', reportId: report, documentType: document_type)
        expect(response).to have_http_status(:created)
        record = Dielca::PdfImport.find_by!(account:, request_id:)
        expect(record.submitter.metadata['report_layout_id']).to eq("#{report}_A4#{stacked ? '_stacked' : ''}")
        confirm_signing(record, signer_name: 'Persona Demo')
        expect(response).to have_http_status(:ok)
        fields = record.submission.template.fields
        timestamp = fields.find { |field| field.dig('preferences', 'dielca_signing_timestamp') }
        signature = fields.find { |field| field['type'] == 'signature' }
        expect(timestamp).to include('readonly' => true, 'required' => false)
        image = Vips::Image.black(180, 70).new_from_image([255, 255, 255])
        png = image.draw_line([0, 0, 0], 10, 50, 45, 15).draw_line([0, 0, 0], 45, 15, 160, 55).pngsave_buffer
        record.submitter.attachments.attach(io: StringIO.new(png), filename: 'fictitious-signature.png',
                                            content_type: 'image/png')
        drawing = record.submitter.attachments.last
        # The date is readonly even if the browser tries to send its own value.
        put submit_form_path(slug: record.submitter.slug), params: {
          completed: 'true', values: { signature['uuid'] => drawing.uuid, timestamp['uuid'] => '01/01/2000' }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(record.submitter.reload.completed_at).to be_nil
        travel_to Time.utc(2026, 11, 1, 14, 5, 6) do
          put submit_form_path(slug: record.submitter.slug), params: {
            completed: 'true', values: { signature['uuid'] => drawing.uuid }
          }
          expect(response).to have_http_status(:ok)
        end
        expected_time = stacked ? "01/11/2026 14:05:06" : "01/11/2026\n14:05:06"
        expect(record.submitter.reload.values[timestamp['uuid']]).to eq(expected_time)
        expect(record.submission.reload.template_fields.flat_map { |field| field['areas'] }.pluck('page'))
          .to all(eq(pages - 1))
        result = Submissions::GenerateResultAttachments.generate_pdfs(record.submitter).values.first
        expect(result.pages.count).to eq(pages)
        images = result.pages[pages - 1][:Resources][:XObject].each.filter_map do |_key, object|
          object if object[:Subtype] == :Image
        end
        expect(images.size).to eq(report == '50000' ? 1 : 2)
        logo = images.find { |image| image[:Width] == 1617 && image[:Height] == 355 }
        if report != '50000'
          expect(logo).to be_present
          expect(logo[:SMask]).to be_present
        end

        result.pages.to_a[0...-1].each { |page| expect(page[:Resources][:XObject]).to be_blank }
        # Optional review artifact contains only the fictitious document generated above.
        if ENV['DIELCA_TEST_PREVIEW'] == 'true' && pages == 1
          result.write("/tmp/dielca-#{report}-#{stacked ? 'stacked' : 'inline'}-timestamp-demo.pdf")
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
          it "imports in #{mode} mode using the approved #{paper == 'A5' ? 'shipment' : 'edited invoice'} positions" do
            params = { signer_mode: mode, reportId: '50001', documentType: 'PostedInvoice',
                       document_number: 'FAC-DEMO' }
            params[:authorized_signers] = '[]' if mode == 'free'
            import(**params)
            expect(response).to have_http_status(:created)
            record = Dielca::PdfImport.find_by!(account:, request_id:)
            expect(record.signer_mode).to eq(mode)
            expect(record.submitter.metadata).to include('report_id' => '50001', 'document_type' => 'PostedInvoice',
                                                         'report_layout_id' => "50001_#{paper}")
            fields = record.submission.template.fields
            expect(fields.flat_map { |field| field['areas'] }.pluck('page')).to all(eq(pages - 1))
            signature = fields.find { |field| field['name'] == 'Firma' }['areas'].sole
            expect(signature['x']).to be_within(0.000001).of(paper == 'A5' ? 0.195 : 0.239)
            expect(signature['y']).to be_within(0.000001).of(paper == 'A5' ? 0.810 : 0.835)
            identity = fields.select { |field| field.dig('preferences', 'dielca_single_line') }
            expect(identity.pluck('readonly')).to all(eq(mode == 'authorized'))
            expect { import(**params) }.not_to change(Submission, :count)
            expect(response).to have_http_status(:created)
            expect(response.parsed_body['submission_id']).to eq(record.submission_id)
          end
        end
      end
    end
  end

  context 'with a native automatic date for an existing pending shipment' do
    let(:bytes) do
      pdf = HexaPDF::Document.new
      page = pdf.pages.add([0, 0, 595.28, 841.89])
      canvas = page.canvas.font('Helvetica', size: 7)
      canvas.text('RECIBÍ CONFORME', at: [33.17, 116])
      canvas.text('Nombre / cargo:', at: [33.17, 104])
      canvas.text('DNI:', at: [33.17, 92])
      canvas.text('Fecha:', at: [33.17, 80])
      StringIO.new.tap { |io| pdf.write(io) }.string
    end

    [
      ['2026-10-29 10:26:30 UTC', '29/10/2026 10:26:30'],
      ['2026-07-15 09:26:30 UTC', '15/07/2026 10:26:30']
    ].each do |instant, expected|
      it "fills a readonly date at completion and renders Canary time for #{instant}" do
        account.update!(timezone: 'Atlantic/Canary')
        import(signer_mode: 'free', authorized_signers: '[]', reportId: '50000', documentType: 'PostedShipment')
        expect(response).to have_http_status(:created)
        record = Dielca::PdfImport.find_by!(account:, request_id:)
        fields = record.submission.template.fields.deep_dup
        timestamp = fields.find { |field| field.dig('preferences', 'dielca_signing_timestamp') }
        timestamp.merge!('type' => 'date', 'readonly' => true, 'required' => false, 'default_value' => '{{date}}')
        timestamp['preferences'].delete('dielca_signing_timestamp')
        timestamp['preferences']['format'] = 'DD/MM/YYYY HH:mm:ss'
        record.submission.template.update!(fields:)
        confirm_signing(record, signer_name: 'Persona Demo')
        expect(response).to have_http_status(:ok)
        signature = fields.find { |field| field['type'] == 'signature' }
        image = Vips::Image.black(180, 70).new_from_image([255, 255, 255])
        png = image.draw_line([0, 0, 0], 10, 50, 45, 15).draw_line([0, 0, 0], 45, 15, 160, 55).pngsave_buffer
        record.submitter.attachments.attach(io: StringIO.new(png), filename: 'fictitious-signature.png',
                                            content_type: 'image/png')
        drawing = record.submitter.attachments.last
        put submit_form_path(slug: record.submitter.slug), params: {
          completed: 'true', values: { signature['uuid'] => drawing.uuid, timestamp['uuid'] => '2000-01-01T00:00:00Z' }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(record.submitter.reload.completed_at).to be_nil
        travel_to Time.parse(instant) do
          put submit_form_path(slug: record.submitter.slug), params: {
            completed: 'true', timezone: 'Asia/Tokyo', values: { signature['uuid'] => drawing.uuid }
          }
          expect(response).to have_http_status(:ok)
        end
        submitter = record.submitter.reload
        value = submitter.values.fetch(timestamp['uuid'])
        expect(Time.iso8601(value)).to eq(submitter.completed_at)
        travel_to Time.parse(instant) + 3.days do
          result = Submissions::GenerateResultAttachments.generate_pdfs(submitter).values.first
          result_io = StringIO.new
          result.write(result_io)
          parsed = Pdfium::Document.open_bytes(result_io.string)
          expect(parsed.get_page(0).text).to include(expected)
          parsed.close
        end
      end
    end
  end

  it 'rejects unknown reports with a clear portal error and creates no unfinished submission' do
    layout # Materialize the configured layout before checking import side effects.
    expect do
      import(reportId: '59999', documentType: 'PostedInvoice')
    end.not_to(change { [Submission.count, Template.count, Dielca::PdfImport.count, ActiveStorage::Blob.count] })
    expect(response).to have_http_status(:unprocessable_content)
    error = response.parsed_body.fetch('error')
    expect(error).to include('code' => 'REPORT_LAYOUT_NOT_CONFIGURED',
                            'message' => Dielca::ReportLayout::NOT_CONFIGURED_MESSAGE)
    expect(error).not_to have_key('sign_url')
    expect(error.fetch('portal_url')).to end_with('/dielca/import-error')
    get URI(error.fetch('portal_url')).request_uri
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('No se puede preparar el documento para firmar',
                                     Dielca::ReportLayout::NOT_CONFIGURED_MESSAGE,
                                     'REPORT_LAYOUT_NOT_CONFIGURED', 'DocuSeal')
    expect(response.body).not_to include(customer_data[:name], signers.first[:name])
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'shows a static portal error without reflecting arbitrary query parameters' do
    get dielca_import_error_path, params: { message: 'REFLECTED-FICTITIOUS-INPUT', reportId: '59999' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include('REFLECTED-FICTITIOUS-INPUT', '59999')
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
      expect(response.parsed_body.dig('error', 'message')).to eq(Dielca::ReportLayout::NOT_CONFIGURED_MESSAGE)
      expect(response.parsed_body.dig('error', 'portal_url')).to end_with('/dielca/import-error')
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
