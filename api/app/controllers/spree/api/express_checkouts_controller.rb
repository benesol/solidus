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
            # Proceed to Confirm
            @order.next!
          end

          # Complete the payment.
          our_payment = @order.unprocessed_payments.last
          # Validate that payment matches final order total- coupon(s) might 
          # have been applied, stealthily.
          Rails.logger.debug("confirm payment: #{our_payment.inspect}")
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