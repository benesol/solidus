require 'pp'

module Spree
  module Core
    module Importer
      class ExpressCheckout < Spree::Core::Importer::Order
        def self.import(user, params)
          params_string = PP.pp(params, '')
          Rails.logger.debug("ExpressCheckout importer params: #{params_string}")
          ActiveRecord::Base.transaction do
          
            # Check for createAndSubmit.  If present, that will modify behavior of request validation and 
            # to what check-out state to leave the Order at.
            create_and_submit_one_call =  !(params["create_and_submit"].nil?) && params["create_and_submit"]
  
            if defined? params[:create_solidus_account] and !params[:create_solidus_account].nil?
              # If need to create Solidus account, do that first.
              # TODO: Handle case where Solidus account with email address already 
              #       exists.  Raise error of some sort.
              Rails.logger.info("Creating new Solidus account for username: #{params[:create_solidus_account][:username]}")
              unless Spree::User.where(["email = ? AND deleted_at IS NOT NULL", 
                  params[:create_solidus_account][:username]]).first
                
                # Set 'user' to the newly-created account, since that is who 
                # this order will be for.
                user = User.create(
                  email: params[:create_solidus_account][:username], 
                  password: params[:create_solidus_account][:password])
                user.save!
              end
            elsif user.blank?
              # TODO: Raise error condition.
              Rails.logger.error("Invalid ExpressCheckout call: user_id nor info to create a new account specified.")
            end
            
            order_create_params = params.slice :currency
            # TODO: Start passing currency in as part of call from C# SolidusProvider
            order_create_params[:currency] = 'CAD'
            # TODO: Start passing store_id in as part of call from C# SolidusProvider?
            #       Get Forbidden Attributes error, so maybe that's why wasn't passing in
            #       store_id ?
            #order_create_params[:store_id] = Spree::Store.default.id
            order = Spree::Order.create! order_create_params
            order.store ||= Spree::Store.default
            order.associate_user!(user)
            order.save!

            # Process 'line_items' / 'adjustments' same as Order importer (our base class)
            # line_items need to have variant children
            if params.key?("order") and params[:order].key?("line_items")
              # Strip everything from the line_items hash except :variant_id, :quantity, :sku ??
              line_items_hash = Hash[(0...params[:order][:line_items].size).zip params[:order][:line_items]]
              #line_items_hash.select {|k,v| Rails.logger.error("key: #{k}, value: #{v}, sliced: #{v.slice(:variant_id, :quantity, :sku)}")}
              line_items_hash_filtered = line_items_hash.select {|k,v| v.slice(:variant_id, :quantity, :sku)}
              create_line_items_from_params(line_items_hash_filtered, order)
            end
            
            # Process 'adjustments'
            if params.key?("adjustments")
              create_adjustments_from_params(params[:adjustments], order)
            end
            
            # Apply 'coupon code' if present.
            if params.key?("coupon_code") && ((params["coupon_code"]).strip).length > 0
              order.coupon_code = params[:coupon_code].strip.downcase
              Rails.logger.debug("Attempting to apply coupon (#{order.coupon_code}) to order: #{order.id}")
              coupon_handler = PromotionHandler::Coupon.new(order).apply
              #if coupon_handler.successful?
                # ??
              #else
                #logger.error("apply_coupon_code_error=#{coupon_handler.error.inspect}")
              #end
            end

            # Advance order state from 'cart' to 'address'
            order.next!
            
            # Validate (using pieces from base class, Order importer) and set order address.
            ensure_country_id_from_params params[:ship_address_attributes]
            ensure_state_id_from_params params[:ship_address_attributes]
            ensure_country_id_from_params params[:bill_address_attributes]
            ensure_state_id_from_params params[:bill_address_attributes]
            
            order.bill_address_attributes = { 
              "zipcode": params[:order][:bill_address][:zipcode], 
              "firstname": params[:order][:bill_address][:firstname], 
              "lastname": params[:order][:bill_address][:lastname], 
              "phone": params[:order][:bill_address][:lastname], 
              "country_id": params[:order][:bill_address][:country_id], 
              "address1": params[:order][:bill_address][:address1], 
              "city": params[:order][:bill_address][:city], 
              "state_name": params[:order][:bill_address][:state_name]
            }
            
            order.ship_address_attributes = { 
              "zipcode": params[:order][:ship_address][:zipcode], 
              "firstname": params[:order][:ship_address][:firstname], 
              "lastname": params[:order][:ship_address][:lastname], 
              "phone": params[:order][:ship_address][:lastname], 
              "country_id": params[:order][:ship_address][:country_id], 
              "address1": params[:order][:ship_address][:address1], 
              "city": params[:order][:ship_address][:city], 
              "state_name": params[:order][:ship_address][:state_name]
            }
            
            # Shouldn't be any shipments for Electronic Delivery.  Just in case.
            order.create_proposed_shipments
            
            # Advance Order State (from Address to Delivery)
            order.next!
            
            # Advance Order State (from Delivery to Payment)
            Rails.logger.debug("order: #{order.inspect}")
            Rails.logger.debug("order # #{order.id} unprocessed_payments: #{order.unprocessed_payments.inspect}")
            order.next!
    
            # TODO: If not subscription renewal, Checkout Payment Assign with payment as credit card
            # Should be able to look up the payment type of the payment_method_id and 
            # see that it is of type 'check'.

            # Set payment_method to 'Externally Paid' check payment method, IF order.total <= 0.0
            if order.total <= 0.00
              externally_paid_payment_method = Spree::PaymentMethod.find_by!(name: 'Externally Paid')
              Rails.logger.debug("order # #{order.id} externally_paid_payment_method: #{externally_paid_payment_method.inspect}")
              payment_method = externally_paid_payment_method
            else 
              payment_method = Spree::PaymentMethod.find(params[:payment_method_id])
            end

            # Just add payment method to wallet, if exists.  Otherwise 
            # use the default payment method, if exists, otherwise, err-out 
            # indicating a payment method needs to be specified.
            Rails.logger.debug("order # #{order.id} payment_method: #{payment_method}")
            if defined? payment_method
              Rails.logger.debug("order # #{order.id} payment_method.type: #{payment_method.type} / params[:payment_source]: #{params[:payment_source].inspect}")
              # TODO: payment_source can be null if using default source in wallet
              wallet_payment_source = nil
              if defined? params[:payment_source] and !params[:payment_source].nil? and !payment_method.is_a?(Spree::PaymentMethod::Check)
                payment_source_attributes = params[:payment_source].to_unsafe_h
                payment_source_attributes[:id] = nil
              
                # 1. If no credit card specified, see if wallet contains default 
                #    payment source.
                wallet_payment_source_id = nil
                if params[:payment_source][:last_digits].empty? or params[:payment_source][:year].empty? or params[:payment_source][:month].empty?
                  Rails.logger.error("order # #{order.id} No credit card specified in express checkout call.  Check for default card in wallet.")
                  if !order.user.wallet.default_wallet_payment_source.nil?
                    Rails.logger.debug("order # #{order.id} Should use default credit card: #{PP.pp(order.user.wallet.default_wallet_payment_source)}")
                  else
                    Rails.logger.error("order # #{order.id} No credit card specified and no default card in wallet.  No way to pay.")
                    raise ArgumentError, "No credit card specified and no default "\
                      "card in wallet to pay with.  Please specify credit card info in Express Checkout API call."
                  end
                else 
                  # Create Solidus credit card object from parameters and stash in wallet.
                  wallet_payment_source = order.user.wallet.add(
                    Spree::CreditCard.new(
                      month: params[:payment_source][:month],
                      year: params[:payment_source][:month],
                      number: params[:payment_source][:last_digits],
                      cc_type: params[:payment_source][:cc_type],
                      name: params[:payment_source][:name],
                      gateway_customer_profile_id: params[:payment_source][:gateway_customer_profile_id],
                      gateway_payment_profile_id: params[:payment_source][:gateway_payment_profile_id]
                    )
                  )
                  
                  if params[:payment_source][:default] == true
                    order.user.wallet.default_wallet_payment_source(wallet_payment_source)
                  end
                  order.save!
                end
              end
              
              # 2. Try to look-up wallet card (that might have just been created) by: 
              #   gateway_payment_profile_id (aka platform.credit_card.gateway_token?)
              #   expiration_year
              #   expiration_month
              #   order.user.wallet.wallet_payment_sources / then go through array looking for match
              # 3. If not in wallet, then create card and add to wallet.
              # 4. Set payment_source_attributes.wallet_payment_source_id as such
              
              if !wallet_payment_source.nil?
                payment_source_attributes = {
                  wallet_payment_source_id: wallet_payment_source.id,
                  verification_value: nil
                }
              elsif payment_method.is_a?(Spree::PaymentMethod::Check)
                # Do nothing here.
              else 
                # Try to get default wallet payment source id, if exists.
                wallet_payment_source = order.user.wallet.default_wallet_payment_source
                if !wallet_payment_source.nil?
                  payment_source_attributes = {
                    wallet_payment_source_id: wallet_payment_source.id,
                    verification_value: nil
                  }
                else
                  # TODO: No default wallet payment source.  This is an error, 
                  #       unless order total <= 0.00
                end
              end

              Rails.logger.debug("order: #{order.inspect}")
              
              filtered_payments_attributes = [
                { 
                  amount: order.total,
                  source_attributes: payment_source_attributes
                }
              ]
              
              if payment_method.is_a?(Spree::PaymentMethod::Check)
                Rails.logger.debug("order # #{order.id} Payment Method should be by check.")
                filtered_payments_attributes = [
                  { 
                    amount: order.total,
                    payment_method_id: payment_method.id
                  }
                ]
              end
              
              Rails.logger.debug("order # #{order.id} filtered_payments_attributes: #{filtered_payments_attributes}")
              Rails.logger.debug("order # #{order.id} payment_method.type: #{payment_method.type}")
              if defined? payment_method.type and 
                payment_method.type == "Spree::PaymentMethod::Check"
                # TODO: If is subscription renewal, Checkout Payment Assign with payment as 'check'?
                # This fails?
                order.payments_attributes=filtered_payments_attributes
              else
                # Some other type of payment...
                # This method will execute the PaymentCreate code.
                OrderUpdateAttributes.new(order, payments_attributes: filtered_payments_attributes).apply

                order.unprocessed_payments.each do |payment|
                  payment.payment_method_id = params[:payment_method_id]
                end

              end
              
            end
            
            unless create_and_submit_one_call
              Rails.logger.debug("order # #{order.id} Did everything except submit Express Checkout order.")
              order.save!
              return order
            end

            # Advance Order State (from Payment to Confirm)
            Rails.logger.info("order # #{order.id} Submitting Express Checkout")
            # Proceed to Confirm
            order.next!
            
            # TODO: What if there is > 1 payment.  Should loop through all payments with total > 0?
            # Complete the payment.
            our_payment = order.unprocessed_payments.last
            # This causes payment method(s) to run the charge.
            our_payment.process!
            # Checkout Payment Capture for 'check' payments and others that do not 'auto-capture'.
            our_payment.capture!
            
            # Proceed to Complete
            order.complete!

            order.save!

            return order
          end
        end
      end
    end
  end
end