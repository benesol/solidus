module Spree
  module Core
    module Importer
      class ExpressCheckout < Spree::Core::Importer::Order
        def self.import(user, params)
          params = params.to_h
          ActiveRecord::Base.transaction do
          
            # Check for createAndSubmit.  If present, that will modify behavior of request validation and 
            # to what check-out state to leave the Order at.
            create_and_submit_one_call =  !(params["create_and_submit"].nil?) && params["create_and_submit"]
  
            #unless params["create_and_submit"].nil? && !params["create_and_submit"]
            #  create_and_submit_one_call = true
            #end
  
            if params.key?("create_solidus_account")
              # If need to create Solidus account, do that first.
              unless Spree::User.first(:conditions => [
                  "email = ? AND deleted_at IS NOT NULL", 
                  params[:create_solidus_account[:username]]])
                  
                fresh_account = User.create(email: params[:create_solidus_account[:username]], 
                  password: params[:create_solidus_account[:password]])
              end
            end
            
            order_create_params = params.slice :currency
            order = Spree::Order.create! order_create_params
            order.associate_user!(user)
            order.save!
            
            # Process 'line_items' / 'adjustments' same as Order importer (our base class)
            if params.key?("line_items")
              create_line_items_from_params(params[:line_items], order)
            end
            
            # Process 'adjustments'
            if params.key?("adjustments")
              create_adjustments_from_params(params[:adjustments], order)
            end
            
            # TODO: Apply 'coupon code' if present.
            if params.key?("coupon_code") && ((params["coupon_code"]).strip).length > 0
              # TODO: What about cases of Customer Referrals where code needs to get created first?
              #       Should express check-out handle this case?
              order.coupon_code = params[:coupon_code].strip.downcase
              coupon_handler = PromotionHandler::Coupon.new(order).apply
              #if coupon_handler.successful?
                # ??
              #else
                #logger.error("apply_coupon_code_error=#{coupon_handler.error.inspect}")
              #end
            end
            # TODO: Advance order state from 'cart' to 'address'
            #//1. move to address state
            #updatedOrder = (transition = await AdvanceOrderState(httpClient, order.number)).Item2 ?? updatedOrder;
            # checkouts_controller:next()
            order.next!
            
            # TODO: Should catch potential errors with?:
            # rescue StateMachines::InvalidTransition => e
            
            unless create_and_submit_one_call
              order.save!
              return order
            end
            
            # TODO: Validate (using pieces from base class, Order importer) and set order address.
            ensure_country_id_from_params params[:ship_address_attributes]
            ensure_state_id_from_params params[:ship_address_attributes]
            ensure_country_id_from_params params[:bill_address_attributes]
            ensure_state_id_from_params params[:bill_address_attributes]
  
            # TODO: HOW DOES THE ADDRESS GET SET?!  Not by the Order Importer.
            #       By the Orders controller, from looks of the routes, but
            #       don't see where the underlying code is?
            # Why in the model:Order object:
            # def bill_address_attributes=(attributes)
            #   self.bill_address = Spree::Address.immutable_merge(bill_address, attributes)
            # end

            # def ship_address_attributes=(attributes)
            #   self.ship_address = Spree::Address.immutable_merge(ship_address, attributes)
            # end
            
            order.bill_address_attributes(:bill_address_attributes)
            order.ship_address_attributes(:ship_address_attributes)
            
            # Shouldn't be any shipments for Electronic Delivery.  Just in case.
            order.create_proposed_shipments
            
            # TODO: Advance Order State (from Delivery to Payment)
            order.next!
            
            # TODO: If not subscription renewal, Checkout Payment Assign with payment as credit card
            # Following likely won't work.  Looking in call Subscription Processor ultimately makes, 
            #   SolidusProvider:SetOrderPaymentOffline(), Only: 
            #   "payments_attributes": { "payment_method_id": "<some string>" } 
            #   is getting set as request body.
            # Should be able to look up the payment type of the payment_method_id and 
            # see that it is of type 'check'.
            # TODO: Verify if anything > order.payment_attributes(...) is necessary.
            payment_id = params['payment_attributes']['payment_method_id']
            
            payment_method = Spree::PaymentMethod.find(payment_id)
            if defined? payment_method 
              if defined? payment_method.type && 
                payment_method.type == "Spree::PaymentMethod::Check"
                
                # TODO: If is subscription renewal, Checkout Payment Assign with payment as 'check'
                order.payment_attributes(params['payment_attributes'])
              else
                # Some other type of payment...
                order.payment_attributes(params['payment_attributes'])
              end
              
            end
            
            if params['payment_source'].key?("year")
              
            end

            
            
            # TODO: Advance Order State (from Payment to Complete)
            
            # TODO: Checkout Payment Capture (needed for 'check' payments that do not 'auto-capture')
            
          end
        end
      end
    end
  end
end