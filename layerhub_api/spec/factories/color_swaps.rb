FactoryBot.define do
  factory :color_swap do
    slice_job { nil }
    layer_number { 1 }
    pause_type { "MyString" }
    color_label { "MyString" }
  end
end
