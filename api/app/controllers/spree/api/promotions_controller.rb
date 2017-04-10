module Spree
  module Api
    class PromotionsController < Spree::Api::ResourceController
      before_action :requires_admin
      before_action :load_promotion, except: [:create]

      helper 'spree/promotion_rules'

      class_attribute :admin_promotion_attributes
      self.admin_promotion_attributes = [:name, :path, :usage_limit, :per_code_usage_limit, :description]
      # From api_helpers: :id, :name, :description, :expires_at, :starts_at, :type, :usage_limit, :match_policy, :advertise, :path

      def create
        authorize! :create, Promotion
        # Use core:app:models:spree:promotion_builder.rb to create promotion
        # TODO: Remove 'base_code' from params passed as 'permitted_resource_params'?
        @promotion_builder = Spree::PromotionBuilder.new(
          permitted_promo_builder_params,
          permitted_resource_params
        )
        @promotion = @promotion_builder.promotion

        if @promotion_builder.perform
          respond_with(@promotion, status: 201, default_template: :show)
        else
          invalid_resource!(@promotion)
        end
      end

      def show
        if @promotion
          respond_with(@promotion, default_template: :show)
        else
          raise ActiveRecord::RecordNotFound
        end
      end

      private

      def requires_admin
        return if @current_user_roles.include?("admin")
        unauthorized && return
      end

      def load_promotion
        @promotion = Spree::Promotion.find_by_id(params[:id]) || Spree::Promotion.with_coupon_code(params[:id])
      end

      def permitted_promotion_attributes
        can?(:admin, Spree::Promotion) ? (super + admin_promotion_attributes) : super
      end

      def permitted_promo_builder_params
        if params[:promotion_builder]
          params[:promotion_builder].permit(:base_code, :number_of_codes)
        else
          {}
        end
      end
    end
  end
end
