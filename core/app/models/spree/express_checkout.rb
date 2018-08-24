module Spree
  class ExpressCheckout < Spree::Base
    self.whitelisted_ransackable_attributes = %w[]

    belongs_to :store, class_name: 'Spree::Store'
    
    has_many :orders

    has_many :line_items, -> { order(:created_at, :id) }, dependent: :destroy, inverse_of: :order
    has_many :variants, through: :line_items
    has_many :products, through: :variants

  end
end