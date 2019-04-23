require_relative 'posts'
require 'json'

class EventHandlers
  class << self
    def delete_all_posts(event:,context:)
      event["Records"].each do |record|
        if record["body"] == "DELETE_ALL"
          count = 0
          begin
            Posts.scan.each do |post|
              post.delete!
              count += 1
            end
            puts "[INFO] Deleted #{count} posts."
          rescue Aws::DynamoDB::Errors => e
            puts "[ERROR] Raised #{e.class} after deleting #{count} entries."
            raise(e)
          end
        else
          puts "[ERROR] Unsupported queue event: #{record.to_json}"
          raise StandardError.new(
            "Unsupported queue command: #{record["body"]}"
          )
        end
      end
    end
  end
end
