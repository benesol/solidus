module Spree
  module Api
    class PromotionsController < Spree::Api::ResourceController
      before_action :requires_admin
      before_action :load_promotion, except: [:create]
      before_action :load_data, except: [:create]

      helper 'spree/promotion_rules'

      class_attribute :admin_promotion_attributes
      self.admin_promotion_attributes = [:name, :path, :usage_limit, :per_code_usage_limit, :description]
      # From api_helpers: :id, :name, :description, :expires_at, :starts_at, :type, :usage_limit, :match_policy, :advertise, :path

      def create
        authorize! :create, Promotion
        # Use core:app:models:spree:promotion_builder.rb to create promotion
        @promotion_builder = Spree::PromotionBuilder.new(
          permitted_promo_builder_params,
          permitted_resource_params,
          permitted_promotion_rules_params,
          permitted_promotion_actions_params
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

      def load_data
        @calculators = Rails.application.config.spree.calculators.promotion_actions_create_adjustments
        @promotion_categories = Spree::PromotionCategory.order(:name)
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

      def permitted_promotion_rules_params
        Rails.logger.info("params[:promotion_rules]: #{params[:promotion_rules].pretty_inspect()}")
        if params[:promotion_rules]
          params[:promotion_rules].permit( [ :type, :product_ids_string, :preferred_match_policy, :user_id ] )
        else
          {}
        end
      end

      def permitted_promotion_actions_params
        Rails.logger.info("params[:promotion_actions]: #{params[:promotion_actions].pretty_inspect()}")
        if params[:promotion_actions]
          params[:promotion_actions].permit( [ :type, calculators: [ :type, :calculable_type, :percentage ]  ] )
        else
          {}
        end
      end
    end
  end
end
