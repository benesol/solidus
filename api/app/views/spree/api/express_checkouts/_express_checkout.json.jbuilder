json.cache! [I18n.locale, express_checkout] do
  json.(express_checkout, *express_checkout_associations)
  json.display_item_total(order.display_item_total.to_s)
  json.total_quantity(order.line_items.sum(:quantity))
  json.display_total(order.display_total.to_s)
  json.display_ship_total(order.display_ship_total)
  json.display_tax_total(order.display_tax_total)
  json.token(order.guest_token)
  json.checkout_steps(order.checkout_steps)
end
