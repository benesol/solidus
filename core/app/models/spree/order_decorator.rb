module Spree
  Order.class_eval do

    # Credit card tokens are to be stored in the Platform database and not in Solidus.
    # Setting this to true will prevent that from happening.
    def temporary_credit_card
      true
    end

  end
end
