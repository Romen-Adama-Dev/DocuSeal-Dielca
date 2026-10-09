# frozen_string_literal: true

class AddSignerModeToDielcaPdfImports < ActiveRecord::Migration[8.1]
  def change
    add_column :dielca_pdf_imports, :signer_mode, :string, null: false, default: 'authorized'
  end
end
