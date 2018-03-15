class Spree::PromotionBuilder
  include ActiveModel::Model

  require 'pp'
  require 'bigdecimal'

  attr_reader :promotion
  attr_accessor :base_code, :number_of_codes, :user

  validates :number_of_codes,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true

  validate :promotion_validity

  class_attribute :code_builder_class
  self.code_builder_class = ::Spree::PromotionCode::BatchBuilder

  # @param promotion_attrs [Hash] The desired attributes for the newly promotion
  # @param attributes [Hash] The desired attributes for this builder
  # @param user [Spree::User] The user who triggered this promotion build
  def initialize(attributes = {}, promotion_attributes = {}, promotion_rules = {}, promotion_actions = {})
    @promotion = Spree::Promotion.new(promotion_attributes)
    super(attributes)
    @promotion_rules = promotion_rules.to_hash
    @promotion_actions = promotion_actions.to_hash

    logMsg = "initializing PromotionBuilder, attributes: #{attributes.pretty_inspect()}, "
    logMsg << "promotion_attributes: #{promotion_attributes.pretty_inspect()}, "
    logMsg << "promotion_rules: #{promotion_rules.pretty_inspect()}, "
    logMsg << "promotion_actions: #{promotion_actions.pretty_inspect()}"
    Rails.logger.info logMsg
  end

  def perform
    if can_build_codes?
      Rails.logger.info "building #{number_of_codes} promotion codes"
      # Avoid getting promotion.id 'not null constraint' error when building promotion code(s) in code_builder()
      @promotion.save
      @promotion.codes = code_builder.build_promotion_codes
    end

    warnMsg = "Created a Promotion consisting of codes: (#{@promotion.codes.pretty_inspect()}) without "
    sendWarnMsg = false

    unless ( @promotion_rules.nil? || @promotion_rules.length == 0 ) && \
      ( @promotion_actions.nil? || @promotion_actions.length == 0 )
      @promotion.save
    end

    unless @promotion_rules.nil? || @promotion_rules.length == 0
      Rails.logger.debug "creating #{@promotion_rules.length} promotion rules"
      @promotion_rules.each do |key, value|
        promotion_rule = @promotion.promotion_rules.create(value)
        Rails.logger.debug "Created promotion rule: #{promotion_rule.pretty_inspect()}"

        if value[:type] == "Spree::Promotion::Rules::User"
          promotion_rule_user_attr = { "promotion_rule_id" => promotion_rule.id, "user_id" => value[:user_id] }
          promotion_rule.promotion_rule_users.create(promotion_rule_user_attr)
        end
      end
    else
      warnMsg << "Rules"
      sendWarnMsg = true
    end

    unless @promotion_actions.nil? || @promotion_actions.length == 0
      Rails.logger.debug "creating #{@promotion_actions.length} promotion actions"
      @promotion_actions.each do |action_key, action_value|
        promotion_action_attrs = { "type" => action_value[:type] }
        promotion_action = @promotion.promotion_actions.create(promotion_action_attrs)

        Rails.logger.debug "Created promotion action: #{promotion_action.pretty_inspect()}"

        unless action_value[:calculators].nil? || action_value[:calculators].length == 0
          calculator_type = nil
          calculable_type = nil
          calculator_percentage = nil

          action_value[:calculators].each do |calcs_key, calcs_value|
            calcs_value.each do |calc_key, calc_value|
              if calc_key == "type"
                calculator_type = calc_value
              elsif calc_key == "calculable_type"
                calculable_type = calc_value
              elsif calc_key == "percentage"
                calculator_percentage = BigDecimal.new(calc_value)
              else
                Rails.logger.warn "Don't handle Promotion Action calculator attribute #{calc_key}"
              end
            end
          end

          Rails.logger.debug "calculator_type: #{calculator_type}, calculable_type: #{calculable_type}, calculator_percentage: #{calculator_percentage}"

          unless calculator_type.nil? || calculator_type != "Spree::Calculator::PercentOnLineItem" || \
            calculable_type.nil? || calculable_type != "Spree::PromotionAction" || calculator_percentage.nil?

            # TODO: delete the default-created calculator.
            Spree::Calculator::PercentOnLineItem.where( \
              calculable_type: "Spree::PromotionAction", calculable_id: promotion_action.id).delete_all

            # Percentage is stored in 'preferences' column as such:
            # "---
            # :percent: !ruby/object:BigDecimal 18:0.24E2
            # "
            # TODO: Figure-out why percentage is always set to 0.
            #calculator_attrs = { "type" => calculator_type, "calculable_type" => calculable_type, \
            #  "calculable_id" => promotion_action.id, "preferred_percent" => calculator_percentage }

            calculator_attrs = { "type" => calculator_type, "calculable_type" => calculable_type, \
              "calculable_id" => promotion_action.id, "preferred_percent" => calculator_percentage }

            promotion_action_calculator = Spree::Calculator::PercentOnLineItem.new(calculator_attrs)
            promotion_action.save
            promotion_action_calculator.save

            # TODO: Figure-out why not seeing this message in log file.
            Rails.logger.debug "Created promotion action calculator: #{promotion_action_calculator.pretty_inspect()}"
          end
        end
      end
    else
      if sendWarnMsg
        warnMsg << ", "
      end
      warnMsg << "Actions"
      sendWarnMsg = true
    end

    if sendWarnMsg
      Rails.logger.warn warnMsg
    end

    return false unless valid?

    @promotion.save
  end

  def number_of_codes=(value)
    @number_of_codes = value.presence.try(:to_i)
  end

  private

  def promotion_validity
    if !@promotion.valid?
      @promotion.errors.each do |attribute, error|
        errors[attribute].push error
      end
    end
  end

  def can_build_codes?
    @base_code && @number_of_codes
  end

  def code_builder
    self.class.code_builder_class.new(@promotion, @base_code, @number_of_codes)
    self.class.code_builder_class.new(
      Spree::PromotionCodeBatch.create!(
        promotion_id: @promotion.id,
        base_code: @base_code,
        number_of_codes: @number_of_codes
      )
    )
  end
end
