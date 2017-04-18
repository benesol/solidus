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

    # TODO: Build promotion rules, actions, calculators, as necessary.
    if promotion_rules.length > 0
      Rails.logger.debug "creating #{promotion_rules.length} promotion rules"
      promotion_rules.each do |key, value|
        Rails.logger.debug "Would have created promotion rule of type: #{value[:type]}"
      end
    else
      warnMsg << "Rules"
      sendWarnMsg = true
    end

    if promotion_actions.length > 0
      Rails.logger.debug "creating #{promotion_actions.length} promotion actions"
      promotion_actions.each do |key, value|
        Rails.logger.debug "Would have created promotion action of type: #{value[:type]}"
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
