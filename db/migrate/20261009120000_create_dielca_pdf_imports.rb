# frozen_string_literal: true

class CreateDielcaPdfImports < ActiveRecord::Migration[8.1]
  def change
    create_table :dielca_pdf_imports do |t|
      t.references :account, null: false, foreign_key: true
      t.string :request_id, null: false
      t.string :pdf_sha256, null: false
      t.string :fingerprint, null: false
      t.references :submission, null: false, foreign_key: true
      t.references :submitter, null: false, foreign_key: true
      t.string :name_field_uuid, null: false
      t.timestamps
    end

    add_index :dielca_pdf_imports, %i[account_id request_id], unique: true
    add_index :dielca_pdf_imports, :submission_id, unique: true,
              name: 'index_dielca_pdf_imports_unique_submission'
  end
end
