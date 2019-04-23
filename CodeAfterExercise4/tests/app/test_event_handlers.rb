require 'minitest/autorun'
require_relative '../../app/event_handlers'

class EventHandlersTest < Minitest::Test
  def test_delete_all_posts
    input_event = {
      "Records" => [
        {
          "messageId" => SecureRandom.uuid,
          "body" => "DELETE_ALL",
          "md5OfBody" => "319f263fe809cba0eb00f8977a972740"
        }
      ]
    }
    mock_post_a = Minitest::Mock.new
    mock_post_b = Minitest::Mock.new
    mock_post_c = Minitest::Mock.new
    post_list = [
      mock_post_a,
      mock_post_b,
      mock_post_c
    ]
    mock_post_a.expect(:delete!, nil, [])
    mock_post_b.expect(:delete!, nil, [])
    mock_post_c.expect(:delete!, nil, [])
    Posts.stub(:scan, post_list) do
      EventHandlers.delete_all_posts(event: input_event, context: nil)
    end
    mock_post_a.verify
    mock_post_b.verify
    mock_post_c.verify
  end

  def test_delete_all_posts_bad_event
    input_event = {
      "Records" => [
        {
          "messageId" => SecureRandom.uuid,
          "body" => "BAD_MESSAGE",
          "md5OfBody" => "6af3db524c14f32b6f183d51c8d04e8a"
        }
      ]
    }
    assert_raises(StandardError) {
      EventHandlers.delete_all_posts(event: input_event, context: nil)
    }
  end
end
