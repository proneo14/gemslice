FactoryBot.define do
  factory :slice_job do
    status { 1 }
    print_asset { nil }
    slicer { "MyString" }
    estimated_time { "MyString" }
    material_used { "MyString" }
    error_message { "MyText" }
  end
end
