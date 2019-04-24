require 'aws-record'

class Posts
  include Aws::Record
  set_table_name(ENV["TABLE_NAME"])
  string_attr :post_uuid, hash_key: true
  string_attr :title
  string_attr :body
  epoch_time_attr :created_at
end
