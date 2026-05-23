FactoryBot.define do
  factory :print_asset do
    name { "MyString" }
    file_type { "MyString" }
    notes { "MyText" }
    project { nil }
  end
end
