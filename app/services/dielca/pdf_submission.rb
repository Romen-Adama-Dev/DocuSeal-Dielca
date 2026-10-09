# frozen_string_literal: true

module Dielca
  class PdfSubmission
    MAX_BYTES = 10.megabytes
    MAX_PAGES = 30
    MAX_SECONDS = 45
    REQUEST_ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    HASH = /\A[0-9a-f]{64}\z/

    class Error < StandardError
      attr_reader :code, :status

      def initialize(code, status = :unprocessable_content)
        @code, @status = code, status
        super(code)
      end
    end

    def self.call(user:, layout:, params:)
      new(user:, layout:, params:).call
    end

    def initialize(user:, layout:, params:)
      @user, @layout, @params = user, layout, params
      @blobs = []
    end

    def call
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      validate_params!
      previous = PdfImport.find_by(account: @user.account, request_id: @request_id)
      return reuse!(previous) if previous

      doc = Pdfium::Document.open_bytes(@bytes)
      raise Error.new('PDF_ENCRYPTED') if doc.encrypted?
      raise Error.new('PDF_PAGE_LIMIT', :content_too_large) unless doc.page_count.between?(1, MAX_PAGES)

      validate_geometry!(doc)

      # Insertion and submission creation commit together. The unique index also
      # prevents two concurrent POSTs from committing different submissions.
      result = ApplicationRecord.transaction do
        template = create_template!
        document = create_document!(template)
        preview!(document, doc)
        role_uuid = template.submitters.first['uuid']
        fields = PdfLayout.fields(@layout, document_uuid: document.uuid,
                                 page: doc.page_count - 1, role_uuid:)
        template.update!(schema: [{ 'attachment_uuid' => document.uuid, 'name' => @document_name }], fields:)
        name_uuid = fields.find { |f| f['name'] == 'Nombre' }['uuid']
        attrs = {
          'name' => @document_name,
          'submitters' => [{ 'role' => 'Cliente', 'name' => @signer_name.presence || 'Identidad por recoger',
                            'external_id' => "bc-#{@request_id}", 'metadata' => @metadata,
                            'values' => @signer_name.present? ? { name_uuid => @signer_name } : {},
                            'send_email' => false, 'send_sms' => false }]
        }.with_indifferent_access
        submissions = Submissions::CreateFromSubmitters.call(
          template:, user: @user, submissions_attrs: [attrs], source: 'api', submitters_order: 'preserved',
          params: { 'send_email' => false, 'send_sms' => false,
                    'require_email_2fa' => false, 'require_phone_2fa' => false }.with_indifferent_access
        )
        submission = submissions.sole
        PdfImport.create!(account: @user.account, request_id: @request_id, pdf_sha256: @pdf_hash,
                          fingerprint: @fingerprint, submission:, submitter: submission.submitters.sole,
                          name_field_uuid: name_uuid)
      end
      @committed = true
      # Search/webhook jobs may be retried by repeating this idempotent endpoint.
      # No signature request dispatch: no mail/SMS contacts are ever stored.
      index!(result)
      result
    rescue ActiveRecord::RecordNotUnique
      cleanup!
      previous = PdfImport.find_by(account: @user.account, request_id: @request_id)
      raise Error.new('IMPORT_BUSY', :service_unavailable) unless previous

      reuse!(previous)
    rescue Pdfium::PasswordError
      raise Error.new('PDF_ENCRYPTED')
    rescue Pdfium::PdfiumError
      raise Error.new('PDF_INVALID')
    ensure
      doc&.close
      cleanup! unless @committed
    end

    private

    def validate_params!
      @request_id = @params[:request_id].to_s
      @pdf_hash = @params[:pdf_sha256].to_s
      raise Error.new('REQUEST_ID_INVALID') unless REQUEST_ID.match?(@request_id)
      raise Error.new('PDF_HASH_INVALID') unless HASH.match?(@pdf_hash)
      raise Error.new('NOTIFICATIONS_FORBIDDEN') unless @params[:send_email] == 'false' && @params[:send_sms] == 'false'
      raise Error.new('COMPLETED_FORBIDDEN') if @params.key?(:completed)

      file = @params[:pdf]
      raise Error.new('PDF_REQUIRED') unless file.is_a?(ActionDispatch::Http::UploadedFile)
      raise Error.new('PDF_SIZE_LIMIT', :content_too_large) if file.size > MAX_BYTES

      @bytes = file.read(MAX_BYTES + 1)
      raise Error.new('PDF_SIZE_LIMIT', :content_too_large) if @bytes.bytesize > MAX_BYTES
      raise Error.new('PDF_INVALID') unless @bytes.start_with?('%PDF-')
      raise Error.new('PDF_HASH_MISMATCH') unless Digest::SHA256.hexdigest(@bytes) == @pdf_hash

      @signer_name = limited_string!(:signer_name, 200)
      @document_name = limited_string!(:document_name, 200)
      raise Error.new('DOCUMENT_NAME_REQUIRED') if @document_name.blank?

      @metadata = { 'request_id' => @request_id, 'pdf_hash' => @pdf_hash,
                    'order_number' => limited_string!(:order_number, 100),
                    'customer' => limited_string!(:customer_name, 200), 'bc_original_pdf' => true }
      @fingerprint = Digest::SHA256.hexdigest(JSON.generate(
        [@pdf_hash, @layout.id, @document_name, @signer_name, @metadata]
      ))
    end

    def limited_string!(key, length)
      value = @params[key] || ''
      raise Error.new('METADATA_INVALID') unless value.is_a?(String) && value.length <= length && !value.include?("\0")

      value.strip
    end

    def reuse!(record)
      raise Error.new('IDEMPOTENCY_CONFLICT', :conflict) unless record.fingerprint == @fingerprint
      raise Error.new('IMPORT_ARCHIVED', :conflict) if record.submission.archived_at || record.submission.template.archived_at

      index!(record)
      record
    end

    def create_template!
      template = Template.create!(account: @user.account, author: @user, name: @document_name,
                                  source: 'api', shared_link: false,
                                  submitters: [{ 'name' => 'Cliente', 'uuid' => SecureRandom.uuid }],
                                  preferences: { 'require_email_2fa' => false, 'require_phone_2fa' => false })
      TemplateAccess.create!(template:, user: @user)
      template
    end

    def create_document!(template)
      # Direct upload of validated bytes: no conversion, decryption or field extraction.
      blob = ActiveStorage::Blob.new(filename: 'pedido-bc.pdf', content_type: 'application/pdf',
                                     metadata: { identified: true, analyzed: true, pdf: {},
                                                 sha256: Base64.urlsafe_encode64(Digest::SHA256.digest(@bytes)),
                                                 bc_pdf_sha256: @pdf_hash })
      @blobs << blob
      blob.upload(StringIO.new(@bytes))
      blob.save!
      document = template.documents.create!(blob:)
      raise Error.new('STORED_HASH_MISMATCH') unless Digest::SHA256.hexdigest(document.download) == @pdf_hash

      document
    end

    def validate_geometry!(doc)
      doc.page_count.times do |number|
        size = doc.page_size(number)
        unless size && size.all? { |n| n.finite? && n.positive? } &&
               (size[0] / size[1]).between?(0.2, 5)
          raise Error.new('PDF_GEOMETRY_INVALID')
        end
      end
    end

    def preview!(document, doc)
      document.metadata['pdf']['number_of_pages'] = doc.page_count
      document.save!
      # Render sequentially to bound memory and keep blob tracking in one thread.
      # Include every page, in particular the last page beyond the upstream default.
      doc.page_count.times do |page_number|
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at > MAX_SECONDS
          raise Error.new('IMPORT_TIME_LIMIT', :service_unavailable)
        end
        page = doc.get_page(page_number)
        begin
          Templates::ProcessDocument.hide_placeholder_widgets(page, hide_empty: !doc.form?)
          page.flatten if doc.form?
          bytes, width, height = page.render_to_bitmap(width: Templates::ProcessDocument::MAX_WIDTH)
          image = Vips::Image.new_from_memory_copy(bytes, width, height, 4, :uchar)
          # Build the blob ourselves to track it before the storage upload can fail.
          data = image.copy(interpretation: :srgb).write_to_buffer('.jpg', Q: 70, strip: true)
          blob = ActiveStorage::Blob.new(filename: "#{page_number}.jpg", content_type: 'image/jpeg',
                                         metadata: { identified: true, analyzed: true, width:, height: })
          @blobs << blob
          blob.upload(StringIO.new(data))
          blob.save!
          ActiveStorage::Attachment.create!(blob:, name: :preview_images, record: document)
        ensure
          page&.close
        end
      end
    end

    def index!(record)
      SearchEntries.enqueue_reindex(record.submission.template)
      SearchEntries.enqueue_reindex(record.submission)
    end

    def cleanup!
      @blobs.each do |blob|
        blob.delete if blob.key.present?
      rescue StandardError
        Rails.logger.error('DIELCA_IMPORT_STORAGE_CLEANUP_REQUIRED')
      end
      @blobs.clear
    end
  end
end
