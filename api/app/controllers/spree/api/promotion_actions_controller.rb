module Spree
  module Api
    class PromotionActionsController < Spree::Api::ResourceController
      before_action :load_promotion, only: [:create, :destroy]
      before_action :validate_promotion_action_type, only: :create

      def create
        @calculators = Spree::Promotion::Actions::CreateAdjustment.calculators
        @promotion_action = @promotion_action_type.new(params[:promotion_action])
        @promotion_action.promotion = @promotion
        if @promotion_action.save
          respond_with(@promotion_action, status: 201, default_template: :show)
        end
        respond_to do |format|
          format.js   { render layout: false }
        end
      end

      def destroy
        @promotion_action = @promotion.promotion_actions.find(params[:id])
        if @promotion_action.destroy
          flash[:success] = Spree.t(:successfully_removed, resource: Spree.t(:promotion_action))
        end
        respond_to do |format|
          format.js   { render layout: false }
        end
      end

      private

      def load_promotion
        @promotion = Spree::Promotion.find(params[:promotion_id])
      end

      def validate_promotion_action_type
        requested_type = params[:action_type]
        promotion_action_types = Rails.application.config.spree.promotions.actions
        @promotion_action_type = promotion_action_types.detect do |klass|
          klass.name == requested_type
        end
        if !@promotion_action_type
          respond_with(@promotion_action, status: 204)
          respond_to do |format|
            format.js   { render layout: false }
          end
        end
      end
    end
  end
end
