# frozen_string_literal: true

class AddSignerSelectionToDielcaPdfImports < ActiveRecord::Migration[8.1]
  def change
    add_column :dielca_pdf_imports, :authorized_signers, :text, null: false, default: '[]'
    add_column :dielca_pdf_imports, :customer_data, :text, null: false, default: '{}'
    add_column :dielca_pdf_imports, :selected_signer_id, :string
    add_column :dielca_pdf_imports, :id_field_uuid, :string
  end
end
