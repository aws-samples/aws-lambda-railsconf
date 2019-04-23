require 'minitest/autorun'
require 'json'
require_relative '../../app/web_api'

class WebApiTest < Minitest::Test
  def test_index
    first_post_time = Time.at(1500000000).utc
    second_post_time = Time.at(1550000000).utc
    post_list = [
      Posts.new(
        post_uuid: "a1",
        title: "First Post",
        body: "Hello, world!",
        created_at: first_post_time
      ),
      Posts.new(
        post_uuid: "b2",
        title: "Second Post",
        body: "Another post.",
        created_at: second_post_time
      )
    ]
    record_collection = Minitest::Mock.new # mocking an itemcollection
    record_collection.expect(:page, post_list, [])
    expected_body = {
      posts: [
        {        
          post_uuid: "a1",
          title: "First Post",
          body: "Hello, world!",
          created_at: first_post_time
        },
        {
          post_uuid: "b2",
          title: "Second Post",
          body: "Another post.",
          created_at: second_post_time
        }
      ]
    }.to_json
    Posts.stub(:scan, record_collection) do
      actual = WebApi.index(event: {}, context: nil)
      assert_equal(expected_body, actual[:body])
      assert_equal(200, actual[:statusCode])
    end
    record_collection.verify
  end

  def test_get
    post_time = Time.at(1500000000).utc
    post = Posts.new(
      post_uuid: "a1",
      title: "First Post",
      body: "Hello, world!",
      created_at: post_time
    )
    expected = {
      statusCode: 200,
      body: {
        post: post.to_h
      }.to_json
    }
    Posts.stub(:find, post) do
      actual = WebApi.get(
        event: {
          "pathParameters" => {
            "uuid" => "a1"
          }
        },
        context: nil
      )
      assert_equal(expected, actual)
    end
    Posts.stub(:find, nil) do
      actual = WebApi.get(
        event: {
          "pathParameters" => {
            "uuid" => "a1"
          }
        },
        context: nil
      )
      assert_equal(404, actual[:statusCode])
    end
  end

  def test_create
    input_event = {
      "body" => {
        title: "New Post",
        body: "Content!"
      }.to_json
    }
    mock = Minitest::Mock.new
    mock.expect(:save, true)
    mock.expect(:to_h, {}) # we don't check the return value in this test
    Posts.stub(:new, mock) do
      SecureRandom.stub(:uuid, "abc123") do
        Time.stub(:now, Time.at(1500000000)) do
          WebApi.create(event: input_event, context: nil)
        end
      end
    end
    mock.verify
  end
end
