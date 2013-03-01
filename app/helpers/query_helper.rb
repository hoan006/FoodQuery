module QueryHelper
  def display_value(value)
    value.to_s.nan? ? value.to_s : "%.2f" % value.to_f
  end
end

