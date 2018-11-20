require 'pp'

module Spree
  module Api
    class ExpressCheckoutsController < Spree::Api::BaseController

      before_action :requires_admin
      before_action :load_express_checkout, except: [:create]

      def create 
        authorize! :create, ExpressCheckout
        # Parse request body that specifies Customer info to create 
        # Solidus account, 'line item(s)' to add to order...
        # Optionally perform entire checkout in single call for 
        # Subscription Renewal use case.  Payment type for that is 
        # 'check' and Customer will already have an account.
        #Rails.logger.debug("Processing Express Checkout create() with request: #{request.inspect}")
        #Rails.logger.debug("HTTP Headers: #{request.headers.inspect}")
        #Rails.logger.debug("HTTP_SPREE_STORE: #{request.headers['HTTP_SPREE_STORE']}")
        #Rails.logger.debug("Processing Express Checkout create() for store: #{current_store.inspect}")
        
        if can?(:admin, ExpressCheckout)
          @order = Spree::Core::Importer::ExpressCheckout.import(determine_express_checkout_user, express_checkout_params)
          Rails.logger.debug("rendering Express Checkout result for: #{@order.inspect}")
          @orders = [@order]
          respond_with(@orders, default_template: :show, status: 201)
        else 
          invalid_resource!(@order)
        end

        #     Existing call to Solidus: api/orders/{0}/apply_coupon_code?coupon_code={1}
        # Optionally, for single call case:
        #   * Order Address details
        #   * Payment info (likely 'check')
        
      end
        
      def confirm
        authorize! :submit, ExpressCheckout
        
        if can?(:admin, ExpressCheckout)
          @order = Spree::Order.find_by_param!(params[:id])

          Rails.logger.debug("confirm order: #{@order.inspect}")
          if @order.state == 'payment'
            # TODO: Add payment method if novel credit card info provided
            @novel_credit_card = params[:payment_source]
            #Rails.logger.debug("Processing Express Checkout Confirm with params: #{params.inspect}")
            #Rails.logger.debug("Express Checkout confirm order novel credit card?: #{@novel_credit_card.inspect}")
            #Rails.logger.debug("Express Checkout Order: #{@order.inspect}")

            
            unless @novel_credit_card.nil?
              # Proceed to Confirm
              # TODO: Set order.unprocessed.payments.each : payment.payment_method_id
              # TODO: Create new wallet entry:
              # Create Solidus credit card object from parameters and stash in wallet.
              @wallet_payment_source = @order.user.wallet.add(
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
              
              Rails.logger.debug("wallet_payment_source.id: #{@wallet_payment_source.id}")
              @payment_source_attributes = {
                wallet_payment_source_id: @wallet_payment_source.id,
                verification_value: nil
              }
              
              filtered_payments_attributes = [
                { 
                  amount: @order.total, 
                  source_attributes: {
                    wallet_payment_source_id: @wallet_payment_source.id,
                    verification_value: nil
                  }
                }
              ]
              
              OrderUpdateAttributes.new(@order, payments_attributes: filtered_payments_attributes).apply

              @order.unprocessed_payments.each do |payment|
                payment.payment_method_id = params[:payment_method_id]
              end

            end

            @order.next!
          end

          # Complete the payment.
          our_payment = @order.unprocessed_payments.last
          # Validate that payment matches final order total- coupon(s) might 
          # have been applied, stealthily.
          #Rails.logger.debug("confirm payment: #{our_payment.inspect}")
          # TODO: Also check that payment amount is at least as much as credit card processor 
          #       minimum.  If not, set to 'External Payment'/check and log an error to 
          #       trigger an alert to Sales/Marketing that we are providing freebies.
          # TODO: Make this $1.00 setting configurable.
          if @order.total <= 0.00 and our_payment.source_type != 
            # TODO: Change payment method to check, if not already.
            externally_paid_payment_method = Spree::PaymentMethod.find_by!(name: 'Externally Paid')
            
            if our_payment.payment_method_id != externally_paid_payment_method.id
              Rails.logger.debug("order # #{@order.id} switching to external payment (check) ")
              our_payment.source_id = nil
              our_payment.source_type = nil
              our_payment.payment_method_id = externally_paid_payment_method.id
              our_payment.amount = 0.0
              our_payment.save!
            end

          elsif our_payment.amount != @order.total
            our_payment.amount = @order.total
          end
          
          # This causes payment method(s) to run the charge.
          our_payment.process!
          # Checkout Payment Capture for 'check' payments and others that do not 'auto-capture'.
          our_payment.capture!

          # Proceed to Complete
          @order.complete!
          @order.save!
          
          @orders = [@order]
          
          respond_with(@orders, default_template: :show, status: 200)
        else 
          invalid_resource!(@order)
        end
      end
      
      # TODO: Have a 'cancel' method on delete if Customer decides they don't 
      #       want to purchase to keep Commerce platform tidy.
      #       (rather than leave orders waiting for completion with live credit 
      #        cards attached)
      
      def requires_admin
        return if @current_user_roles.include?("admin")
        unauthorized && return
      end

      def load_express_checkout
        @order = Spree::Order.find_by(id: params[:id])
      end
      
      # @api public
      def determine_express_checkout_user
        if params[:user_id].present?
          return Spree.user_class.find(params[:user_id])
        else
          return nil
        end
      end
      
      def permitted_express_checkout_attributes
        can?(:admin, Spree::ExpressCheckout) ? admin_express_checkout_attributes : express_checkout_attributes
      end
      
      def express_checkout_params
        params
      end
    
    end
  end
end