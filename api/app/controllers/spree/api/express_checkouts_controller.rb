module Spree
  module Api
    class ExpressCheckoutsController < Spree::Api::BaseController
      before_action :requires_admin
      before_action :load_express_checkout, except: [:create]

      def create 
        authorize! :create, ExpressCheckout
        # TODO: Parse request body that specifies Customer info to create 
        #       Solidus account, 'line item(s)' to add to order...
        #       Optionally perform entire checkout in single call for 
        #       Subscription Renewal use case.  Payment type for that is 
        #       'check' and Customer will already have an account.
        # Needs to accept input for:
        #   * Customer info for creation of Solidus account
        #     Existing call to Solidus: api/users/?user[email]={0}&user[password]={1}
        #     JSON version here...
=begin
{
  “createSolidusAccount”: {
     “username”: “<Username>”,
     “password”: “<Password>"
  },
  
}
=end
        #     Here's example of 1-API call order submission request body JSON:
=begin
{
  “createSolidusAccount”: {
     “username”: “<Username>”,
     “password”: “<Password>"
  },
  "createAndSubmit": <true | false>,
  “order”: {
    “user_id”: “<Solidus userid>”,
    “line_items”: [
      {
        “variant_id”: “<Solidus variant ID>”, 
        “quantity”: <quantity integer>
      },
      “adjustments”: [
        {
          “amount”: “<some amount>”,
          “label”: “<some label>”,
          “source_type”: “<some type of source>”,
        }
      ]
    ],
    "bill_address_attributes": {
      "firstname": "<FirstName>",
      "lastname": "<LastName>",
      "phone": "<PhoneNumber>",
      "address1": "<StreetAddress or Unknown>",
      "city": "<Locality>",
      "zipcode": "<PostalCode>",
      "state_name": "<Region>",
      "country_iso": "<CountryCodeAlpha2>"
    },
    "ship_address_attributes": {
      "firstname": "<FirstName>",
      "lastname": "<LastName>",
      "phone": "<PhoneNumber>",
      "address1": "<StreetAddress or Unknown>",
      "city": "<Locality>",
      "zipcode": "<PostalCode>",
      "state_name": "<Region>",
      "country_iso": "<CountryCodeAlpha2>"
    }
  },
  "coupon_code": "<some coupon code>",
  "payments_attributes": [ “payment_method_id”: “<paymentMethodId>” ],
  “payment_source”: {
    “<creditCardPaymentMethodId>”: {
      “gateway_customer_profile_id”: "<GatewayCustomerId>”,
      “gateway_payment_profile_id”: “<GatewayToken>”,
      “year”: “<ExpirationYear>”,
      “month”: “<ExpirationMonth>”,
      “day”: “<ExpirationDay>”,
      “name”: “<CustomerName>"
    }
  }
}
=end
        #   * Line Items to order
        #     Existing call to Solidus: api/orders/?order[user_id]={0}&order[line_items][0][variant_id]={1}&
        #       order[line_items][0][quantity]={2}&order[adjustments][0][amount]={3}&
        #       order[adjustments][0][label]={4}&order[adjustments][0][source_type]={5}
        #     JSON version here...
=begin
{
  "createAndSubmit": <true | false>,
  “order”: {
    “user_id”: “<Solidus userid>”,
    “line_items”: [
      {
        “variant_id”: “<Solidus variant ID>”, 
        “quantity”: <quantity integer>
      },
      “adjustments”: [
        {
          “amount”: “<some amount>”,
          “label”: “<some label>”,
          “source_type”: “<some type of source>”,
        }
      ]
    ]
  }
}
=end
        #   * Promotion code
=begin
{
  "order": {
    "coupon_code": "<some coupon code>"
  }
}
=end
        #     Existing call to Solidus: api/orders/{0}/apply_coupon_code?coupon_code={1}
        # Optionally, for single call case:
        #   * Order Address details
        #   * Payment info (likely 'check')
        
      end
        
      def payment
        #authorize! :create, ExpressCheckout
        # Needs to accept input for:
        #   * Order Address details
        #     Existing call to Solidus: api/checkouts/<order_number>.json / message body JSON:
        #   * Payment info
        #     api/checkouts/<order_number>.json / message body JSON:
        #     JSON example here...
=begin
{
  "order": {
    "bill_address_attributes": {
      "firstname": "<FirstName>",
      "lastname": "<LastName>",
      "phone": "<PhoneNumber>",
      "address1": "<StreetAddress or Unknown>",
      "city": "<Locality>",
      "zipcode": "<PostalCode>",
      "state_name": "<Region>",
      "country_iso": "<CountryCodeAlpha2>"
    },
    "ship_address_attributes": {
      "firstname": "<FirstName>",
      "lastname": "<LastName>",
      "phone": "<PhoneNumber>",
      "address1": "<StreetAddress or Unknown>",
      "city": "<Locality>",
      "zipcode": "<PostalCode>",
      "state_name": "<Region>",
      "country_iso": "<CountryCodeAlpha2>"
    },
    "payments_attributes": [ “payment_method_id”: “<paymentMethodId>” ],
  },
  “payment_source”: {
    “<creditCardPaymentMethodId>”: {
      “gateway_customer_profile_id”: "<GatewayCustomerId>”,
      “gateway_payment_profile_id”: “<GatewayToken>”,
      “year”: “<ExpirationYear>”,
      “month”: “<ExpirationMonth>”,
      “day”: “<ExpirationDay>”,
      “name”: “<CustomerName>"
    }
  }
}
=end

      end
        
      def confirm
        #authorize! :create, ExpressCheckout
        # Doesn't need any input.  Make it so.
      end
      
      def requires_admin
        return if @current_user_roles.include?("admin")
        unauthorized && return
      end

      def load_express_checkout
        @order = Spree::Order.find_by(id: params[:id])
      end
    
    end
  end
end