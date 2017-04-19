class Spree::PromotionBuilder
  include ActiveModel::Model

  require 'pp'

  attr_reader :promotion
  attr_accessor :base_code, :number_of_codes, :user

  validates :number_of_codes,
    numericality: { only_integer: true, greater_than: 0 },
    allow_nil: true

  validate :promotion_validity

  class_attribute :code_builder_class
  self.code_builder_class = ::Spree::PromotionCode::CodeBuilder

  # @param promotion_attrs [Hash] The desired attributes for the newly promotion
  # @param attributes [Hash] The desired attributes for this builder
  # @param user [Spree::User] The user who triggered this promotion build
  def initialize(attributes = {}, promotion_attributes = {}, promotion_rules = {}, promotion_actions = {})
    @promotion = Spree::Promotion.new(promotion_attributes)
    super(attributes)
    @promotion_rules = promotion_rules
    @promotion_actions = promotion_actions

    logMsg = "initializing PromotionBuilder, attributes: #{attributes.pretty_inspect()}, "
    logMsg << "promotion_attributes: #{promotion_attributes.pretty_inspect()}, "
    logMsg << "promotion_rules: #{promotion_rules.pretty_inspect()}, "
    logMsg << "promotion_actions: #{promotion_actions.pretty_inspect()}"
    Rails.logger.info logMsg
  end

  def perform
    if can_build_codes?
      Rails.logger.info "building #{number_of_codes} promotion codes"
      @promotion.codes = code_builder.build_promotion_codes
    end

    warnMsg = "Created a Promotion consisting of codes: (#{@promotion.codes.pretty_inspect()}) without "
    sendWarnMsg = false

    unless @promotion_rules.nil? || @promotion_rules.length == 0
      @promotion.save
      Rails.logger.debug "creating #{@promotion_rules.length} promotion rules"
      @promotion_rules.each do |key, value|
        Rails.logger.debug "Would have created promotion rule of type: #{value[:type]}"
        #promo_rule = Spree::PromotionRule.new(value)
        @promotion.promotion_rules.create(value)
        #Rails.logger.debug "Here's preview of promotion rule: #{promo_rule.pretty_inspect()}"
      end
    else
      warnMsg << "Rules"
      sendWarnMsg = true
    end

    unless @promotion_actions.nil? || @promotion_actions.length == 0
      Rails.logger.debug "creating #{@promotion_actions.length} promotion actions"
      @promotion_actions.each do |action_key, action_value|
        Rails.logger.debug "Would have created promotion action of type: #{action_value[:type]}"
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
                calculator_percentage = calc_value
              else
                Rails.logger.warn "Don't handle Promotion Action calculator attribute #{calc_key}"
              end
            end
          end

          Rails.logger.debug "calculator_type: #{calculator_type}, calculable_type: #{calculable_type}, calculator_percentage: #{calculator_percentage}"

          unless calculator_type.nil? || calculator_type != "Spree::Calculator::PercentOnLineItem" || \
            calculable_type.nil? || calculable_type != "Spree::PromotionAction" || calculator_percentage.nil?

            daMsg = "Would have created promotion action calculator of type: #{calculator_type}, "
            daMsg << "calculable_type: #{calculable_type}, calculator_percentage: #{calculator_percentage}"

            Rails.logger.debug daMsg
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
  end
end
