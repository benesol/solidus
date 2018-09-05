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