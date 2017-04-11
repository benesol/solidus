module Spree
  module Api
    class PromotionRulesController < Spree::Api::ResourceController
      helper 'spree/promotion_rules'

      before_action :load_promotion, only: [:create, :destroy]
      before_action :validate_promotion_rule_type, only: :create

      def create
        @promotion_rule = @promotion_rule_type.new(params[:promotion_rule])
        @promotion_rule.promotion = @promotion
        if @promotion_rule.save
          respond_with(@promotion_rule, status: 201, default_template: :show)
        end
      end

      def destroy
        @promotion_rule = @promotion.promotion_rules.find(params[:id])
        if @promotion_rule.destroy
          respond_with(@promotion_rule, status: 204)
        end
      end

      private

      def load_promotion
        @promotion = Spree::Promotion.find(params[:promotion_id])
      end

      def validate_promotion_rule_type
        requested_type = params[:promotion_rule].delete(:type)
        promotion_rule_types = Rails.application.config.spree.promotions.rules
        @promotion_rule_type = promotion_rule_types.detect do |klass|
          klass.name == requested_type
        end
        if !@promotion_rule_type
          # TODO: Send reasonable error response?
          invalid_resource!(@promotion_rule_type)
        end
      end
    end
  end
end
