class ::Spree::PromotionCode::BatchBuilder
  attr_reader :promotion_code_batch
  delegate :promotion, :number_of_codes, :base_code, to: :promotion_code_batch

  class_attribute :random_code_length, :batch_size, :sample_characters, :join_characters
  self.random_code_length = 6
  self.batch_size = 1_000
  self.sample_characters = ('a'..'z').to_a + (2..9).to_a.map(&:to_s)
  self.join_characters = "_"

  def initialize(promotion_code_batch)
    @promotion_code_batch = promotion_code_batch
  end

  def build_promotion_codes
    generated_codes = generate_random_codes
    promotion_code_batch.update!(state: "completed")
    generated_codes
  rescue => e
    promotion_code_batch.update!(
      error: e.inspect,
      state: "failed"
    )
    raise e
  end

  private

  def generate_random_codes
    total_batches = (number_of_codes.to_f / self.class.batch_size).ceil
    all_generated_codes = Array.new

    total_batches.times do |i|
      codes_for_current_batch = Set.new

      if self.number_of_codes == 1
        # If number_of_codes is 1, then create a single code of base_code and no random portion.                              
	      codes_for_current_batch.add(base_code)
      else 
        codes_to_generate = [self.class.batch_size, number_of_codes - i * batch_size].min
        while codes_for_current_batch.size < codes_to_generate
          new_codes = Array.new(codes_to_generate) { generate_random_code }.to_set
          codes_for_current_batch += get_unique_codes(new_codes)
        end
      end

      codes_for_current_batch.map do |value|
        all_generated_codes.push(promotion.codes.build(value: value, promotion_code_batch: promotion_code_batch))
      end

      promotion.save!

      # We have to reload the promotion because otherwise all promotion codes
      # we are creating will remain in memory. Doing a reload will remove all
      # codes from memory.
      promotion.reload
    end
    all_generated_codes
  end

  def generate_random_code
    suffix = Array.new(self.class.random_code_length) do
      sample_characters.sample
    end.join

    "#{base_code}#{join_characters}#{suffix}"
  end

  def get_unique_codes(code_set)
    code_set - Spree::PromotionCode.where(value: code_set.to_a).pluck(:value)
  end
end
