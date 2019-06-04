# Going Serverless with Ruby on AWS Lambda

In this lab, we're going to develop and deploy both web and event-based functions to AWS Lambda, as well as introduce continuous deployment to our application, and then show how we can incorporate web frameworks. We'll also have an exercise to explore options for alarm configuration.

## Exercise -1: How To Complete This Workshop

A Note: This advice applies primarily to the live workshop. If you're running this workshop on your own, opening a GitHub issue is the easiest way to get help.

The exercises in this workshop are meant to be completed in order. Ideally, you've already completed Exercise 0 and installed the dependencies for this workshop. If not, I recommend starting right away - the introductory slides will be on video after the conference.

At the live workshop, we'll be going around to help throughout, and occasionally demoing certain parts of the process live. If you fall behind, or if an instruction is confusing and you get stuck, I've included snapshots of what the code should look like after exercises 1, 2, 3, and even 4 (the optional/take-home exercise) are complete. Feel free to compare code, or copy one of those snapshots and resume from them.

Ask questions early and often! We'll be demoing answers to common questions as they come up, but most of the time is intended for us to help you one-on-one! Take advantage.

Some pointers to keep in mind:

* Make sure you pay attention to `--region` settings, when used. One key point is that the region your source bucket is in, much match the region you deploy to.
* Because the template file is YAML formatted, indentation matters. If you're getting a deployment error that doesn't make sense, there's a good chance your YAML file isn't indented properly somewhere.
* Make extra sure that you're using Ruby 2.5 in your command line where you build dependencies. If your shell defaults to Ruby 2.6, you may end up with mysterious errors after deploying, because vendored dependency file paths are sensitive to the Ruby minor version in use. Ruby 2.5.5 is recommended, but any Ruby version in the 2.5.x family should work.

## Exercise 0: Setup

### Set Up Ruby 2.5

When you build your AWS Lambda dependencies, you'll want to use containerized builds or to ensure you're using Ruby 2.5. I recommend you use `rbenv` or `rvm` to manage your versions of Ruby:

* [rbenv Installation Instructions](https://github.com/rbenv/rbenv#installation)
* [rvm Installation Instructions](https://rvm.io/rvm/install)

It is important to make sure that you're using Ruby 2.5. Any minor version works, but the latest (2.5.5) is recommended as a best practice.

```shell
# in rbenv
rbenv install 2.5.5 # if not already installed
export RBENV_VERSION=2.5.5

# in rvm
rvm install 2.5.5 # if not already installed
rvm use 2.5.5

# verification
ruby -v
```

If you have set your version for your Ruby version manager but it doesn't match the output of `ruby -v`, then review your Ruby version manager setup instructions (you may have to refresh your shell environment, for example).

### Set Up AWS CLI

If you do not have the AWS CLI installed on your system, I recommend you use the [bundled installer](https://docs.aws.amazon.com/cli/latest/userguide/install-bundle.html) for the easiest installation experience. I recommend using the latest version of the AWS CLI for this lab.

### Set Up AWS Shared Credential File

You will need AWS credentials in order to perform your deployments via AWS CloudFormation, and your role used will need to have permissions to create IAM roles. If you do not have credentials configured on your development environment, you can follow this [guide in the AWS CLI developer guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html).

Ensure that you place the credentials you're going to use in your "default" profile, or if you have your own profile setup that you're using the correct AWS_PROFILE environment variable setting.

### Set Up AWS SAM CLI & Docker

The installation steps for AWS SAM CLI are documented in the [AWS SAM CLI developer guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html). Note also that Docker installation instructions are included in this guide.

### Create an S3 Bucket

You will need to have an S3 bucket to use for storing your code artifacts when deploying your application. You may use an existing bucket (just make sure to note its region for later), or you can create one using the AWS CLI like so:

```shell
# substitute a unique name for your bucket
export RAILSCONF_SOURCE_BUCKET=my-railsconf-source-bucket
aws s3api create-bucket --bucket $RAILSCONF_SOURCE_BUCKET --region us-west-2 --create-bucket-configuration LocationConstraint=us-west-2
```

Because S3 bucket names are globally unique, don't use that exact bucket name. Just ensure that:

1. You note which region you created your bucket it, as you'll need to also deploy your application to this region later. If you don't specify a region, it can be assumed to be `us-east-1`. Or, if using an existing bucket, note the region it was created in.
2. You keep track of the bucket name you used.

## Exercise 1: Your First AWS Lambda Web API Method

In this exercise, we're going to create our first web-based serverless APIs. We're also going to incorporate an Amazon DynamoDB database, and the `aws-record` gem to interact with the database.

### 1.1: Create the SAM Project

Run `sam init --runtime ruby2.5 --name railsconf2019` to create the project we're going to use for the remainder of the exercise. You can substitute any name you like. You will see the following file structure within your project folder:

```
├── Gemfile
├── README.md
├── hello_world
│   ├── Gemfile
│   └── app.rb
├── template.yaml
└── tests
    └── unit
        └── test_handler.rb
```

You'll notice that we have two Gemfiles in this case. The mental model to use for this is that the root Gemfile is used for testing, and the Gemfile within your function directory ('hello_world' in this case, but we're going to replace it) determines what is actually deployed to AWS Lambda.

The template generated is a fully operational example app, but we're going to clear away some of what was generated for us and recreate it ourselves to better understand what's going on.

For the moment, we're going to:

1. Delete the `hello_world` folder and all its contents.
2. Delete the `tests` folder and all its contents.
3. For the top level `Gemfile`, reduce it to test dependencies only:

`Gemfile`
```ruby
source "https://rubygems.org"

# Load app Gemfile dependencies
eval(IO.read("app/Gemfile"), binding)

group :test do
  gem 'minitest', '~> 5.11'
end
```

Finally, delete the stub function from `template.yaml`, leaving us with the following:

`template.yaml`
```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: >
    railsconf2019

    Sample SAM Template for railsconf2019

Globals:
  Function:
    Timeout: 3

Resources:

Outputs:
  ApiEndpoint:
    Description: "API Gateway endpoint URL for Prod stage"
    Value: !Sub "https://${ServerlessRestApi}.execute-api.${AWS::Region}.amazonaws.com/Prod/"
```

From this point, we will add in each component that we need.

### 1.2: Adding a DynamoDB Table

Let's go ahead and create a new folder where our app definition will live:

```
mkdir app
cd app/
touch Gemfile
touch web_api.rb
touch posts.rb
```

After we do this, we need to add our DynamoDB table to our application template, and define it in `posts.rb`. First, we're going to edit `template.yaml` in the root directory of our project, and add the following as our first resource:

`template.yaml`
```yaml
Resources:
  PostsTable:
    Type: AWS::Serverless::SimpleTable
    Properties:
      PrimaryKey:
        Name: post_uuid
        Type: String
```

We then need to create the equivalent table in `posts.rb` like so:

`app/posts.rb`
```ruby
require 'aws-record'

class Posts
  include Aws::Record
  set_table_name(ENV["TABLE_NAME"])
  string_attr :post_uuid, hash_key: true
  string_attr :title
  string_attr :body
  epoch_time_attr :created_at
end
```

And, ensure the `app/Gemfile` has our required dependency:

`app/Gemfile`
```ruby
source "https://rubygems.org"

gem 'aws-record', '~> 2'
```

Now, if you run `bundle install` in your project root directory, you'll have the dependencies you need to continue, and your table is ready.

### 1.3: Failing Unit Tests

```
mkdir -p tests/app
cd tests/app
touch test_web_api.rb
```

We want to test the `WebApi` suite of handlers, specifically for basic `index`, `get`, and `create` behavior. In this case, copy the following test file into `test_web_api.rb`, so you can see tests passing as you go:

`tests/app/test_web_api.rb`
```ruby
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
    record_collection = Minitest::Mock.new # mocking an ItemCollection
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
```

### 1.4: Implementation of the Web API

We're going to be putting our AWS Lambda handlers into a class, so let's put a class skeleton into `web_api.rb`:

`app/web_api.rb`
```ruby
require_relative 'posts'

class WebApi
  class << self
  end
end
```

If we run `ruby tests/app/test_web_api.rb` we will now find that our three handlers are not defined, so let's flesh them out one by one and get our tests to pass.

#### 1.4.1: Index Function

We're going to start by putting the method signature for an AWS Lambda handler into the `WebApi` class like so:

`app/web_api.rb`
```ruby
class WebApi
  class << self
    def index(event:,context:)
    end
  end
end
```

There are a few important notes to understand before we proceed:

* AWS Lambda handlers inside a class should be class methods, not instance methods. When we define the handler `web_api.WebApi.index`, we're telling AWS Lambda to load the file `web_api.rb`, and then call `WebApi.index`. If you define an instance method, you'll end up with a runtime exception (or with our test suite, the tests won't pass).
* Your handler needs to accept the `event:` keyname argument (or hash argument). The AWS Lambda runtime uses this parameter to pass the calling event, which in this case will be a web request from Amazon API Gateway.
* Your handler also needs to accept the `context:` keyname argument (or hash argument, which for this method you can ignore). The context object provides [a number of useful helper methods](https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html) which can be especially helpful for debugging or for long-running functions that may need to be aware of the execution deadline. We won't need any context methods for this workshop, but they're handy to know.

To implement the `index` method, we're going to scan over our DynamoDB table and return JSON representations of the posts within. Conceptually, this is an API which takes no arguments, and the response hash includes the `posts` keyword for which the value is an array with up to 25 posts:

`app/web_api.rb`
```ruby
def index(event:,context:)
  posts = Posts.scan(limit: 25).page.map { |p| p.to_h }
  return {
    statusCode: 200,
    body: { posts: posts }.to_json
  }
end
```

You should see `ruby tests/app/test_web_api.rb` passing for the index test case.

A couple of notes about this implementation:

* This implementation, to avoid a full table scan, returns only a single 'page' of up to 25 results. The `aws-record` library provides this and other methods to help you implement paginated APIs, but we won't worry about adding pagination yet.
* API Gateway expects your AWS Lambda function to return a hash, with the following keys:
    * `statusCode`: The HTTP status code to return to the caller.
    * `body`: Needs to be a string, which will be returned to the caller. In our case, we call `#to_json` on the hash representation of our response.
    * `headers`: If desired, you can also specify response headers. This is optional and we are choosing not to do so in this handler.

Finally, we need to add our handler to our `template.yaml` file, so that it can be packaged and deployed. We put the following under the `Resources` key:

`template.yaml`
```yaml
Resources:
  WebApiIndex:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: app/
      Handler: web_api.WebApi.index
      Runtime: ruby2.5
      Policies:
        - DynamoDBReadPolicy:
            TableName: !Ref PostsTable
      Environment:
        Variables:
          TABLE_NAME: !Ref PostsTable
      Events:
        ApiIndex:
          Type: Api
          Properties:
            Path: /posts
            Method: GET
```

#### Bonus: Deploy and Run Your First Lambda Function

At this point, though we haven't completed all of our APIs, we can deploy and see this running on AWS!

```shell
sam build
sam package --template-file .aws-sam/build/template.yaml --output-template-file packaged.yaml --s3-bucket $RAILSCONF_SOURCE_BUCKET
sam deploy --template-file packaged.yaml --stack-name railsconf2019 --capabilities CAPABILITY_IAM --region us-west-2
aws cloudformation describe-stacks --stack-name railsconf2019 --region us-west-2 --query 'Stacks[].Outputs'
```

If you did not set `$RAILSCONF_SOURCE_BUCKET` in Exercise 0, make sure you set it or use your source bucket name above.

The final command should give you an endpoint for your API, and if you add `posts` to the end of it for your path, you can call it with curl like so:

```shell
export RAILSCONF_API_ENDPOINT=https://12my34api56id.execute-api.us-west-2.amazonaws.com/Prod/posts
curl $RAILSCONF_API_ENDPOINT
```

Make sure to substitute your actual API path here as returned from CloudFormation. You should see an empty response like `{"posts":[]}`, but you've deployed a function to AWS Lambda! We'll finish the implementation now.

#### 1.4.2: Get Function

At this point, we can see a pattern for adding new web API functions:

1. Create a new handler function that returns an API Gateway-formatted response hash.
2. Add the handler definition to `template.yaml`.

Our `get` function will also look at parsing raw event inputs. One thing to keep in mind is that we're doing this in the most manual way. Libraries built on top of AWS Lambda can and do abstract this away for you.

Let's start with the code we need:

`app/web_api.rb`
```ruby
def get(event:,context:)
  post_id = event["pathParameters"]["uuid"]
  post = Posts.find(post_uuid: post_id)
  if post
    return {
      statusCode: 200,
      body: { post: post.to_h }.to_json
    }
  else
    return {
      statusCode: 404,
      body: { error: "Post #{post_id} not found!" }.to_json
    }
  end
end
```

After you confirm you're down to a single error when running `ruby tests/app/test_web_api.rb` we can add the resource to our `template.yaml` file:

`template.yaml`
```yaml
WebApiGet:
  Type: AWS::Serverless::Function
  Properties:
    CodeUri: app/
    Handler: web_api.WebApi.get
    Runtime: ruby2.5
    Policies:
      - DynamoDBReadPolicy:
          TableName: !Ref PostsTable
    Environment:
      Variables:
        TABLE_NAME: !Ref PostsTable
    Events:
      ApiGet:
        Type: Api
        Properties:
          Path: /posts/{uuid}
          Method: GET
```

One key difference can be found in the `Path` value we set. When you use the `/posts/{uuid}` syntax, API Gateway will automatically parse and pass along values put in the actual path. So if a user makes a GET request to `/posts/my-post-id`, the `event["pathParameters"]["uuid"]` value will be the string `'my-post-id'`.

#### 1.4.3: Create Function

When creating a new post, we have to think a bit more about input validation. Users pass in JSON as the request body, which we parse for the post field values. Since we only accept two parameters from our user, we can fairly easily implement the allowed parameters pattern.

`app/web_api.rb`
```ruby
def create(event:,context:)
  params = _create_params(event["body"])
  params[:post_uuid] = SecureRandom.uuid
  params[:created_at] = Time.now
  post = Posts.new(params)
  if post.save
    return {
      statusCode: 200,
      body: { post: post.to_h }.to_json
    }
  else
    return {
      statusCode: 500,
      body: { error: "Failed to create new post." }
    }
  end
end

private
def _create_params(body_input)
  ret = {}
  json = JSON.parse(body_input, symbolize_names: true)
  ret[:title] = json[:title]
  ret[:body] = json[:body]
  ret
end
```

(Note: The unit test mocking behavior is a bit particular to exactly how you write the function definition. While it's perfectly valid to set `:post_uuid` and `:created_at` on the new `post` object before saving, you would have to set new mock expectations if you do so.)

After we add our final function definition to `template.yaml`, we are ready to deploy to AWS:

`template.yaml`
```yaml
WebApiCreate:
  Type: AWS::Serverless::Function
  Properties:
    CodeUri: app/
    Handler: web_api.WebApi.create
    Runtime: ruby2.5
    Policies:
      - DynamoDBCrudPolicy:
          TableName: !Ref PostsTable
    Environment:
      Variables:
        TABLE_NAME: !Ref PostsTable
    Events:
      ApiCreate:
        Type: Api
        Properties:
          Path: /posts
          Method: POST
```

Note here that we are using a different policy for DynamoDB access which allows for calling the `#put_item` API on our table. This entire time, we've been ensuring that our AWS Lambda functions have the minimal set of permissions necessary for them to function properly, an important best practice.

### 1.5: Deploying to AWS

Run the following set of commands, using the bucket from Exercise 0, and the region of the bucket for `us-west-2` if you used another region. The region must match the region of the bucket in which you're storing your function source.

```
sam build
sam package --template-file .aws-sam/build/template.yaml --output-template-file packaged.yaml --s3-bucket $RAILSCONF_SOURCE_BUCKET
sam deploy --template-file packaged.yaml --stack-name railsconf2019 --capabilities CAPABILITY_IAM --region us-west-2
aws cloudformation describe-stacks --stack-name railsconf2019 --region us-west-2 --query 'Stacks[].Outputs'
```

The final command should include your API endpoint, which you can call with curl. For example:

```
export RAILSCONF_API_ENDPOINT=https://12my34api56id.execute-api.us-west-2.amazonaws.com/Prod/posts
curl $RAILSCONF_API_ENDPOINT
```

That second command should return `{"posts":[]}`, which is coming from AWS Lambda!

### 1.6: Using Your API

Try the following commands:

```
curl $RAILSCONF_API_ENDPOINT/missingid
curl -d '{"title":"First Post!","body":"Hello, Lambda!"}' $RAILSCONF_API_ENDPOINT
curl $RAILSCONF_API_ENDPOINT/uuidfromlastresponse
curl -d '{"title":"No Body Post"}' $RAILSCONF_API_ENDPOINT
curl $RAILSCONF_API_ENDPOINT
```

As you run these commands, you can see your JSON-based serverless API in action!

## Exercise 2: Your First AWS Lambda Event-Trigger Methods

AWS Lambda has multiple ways to invoke handlers. You can directly invoke via the AWS SDKs/CLI/Console, you can invoke as a web API (like we have done in Exercise 1), and you can also trigger your handlers from a number of different event sources. Some examples include:

* Amazon S3 Object Lifecycle Events
* Amazon SQS Queue Processing
* Amazon SNS Event Processing
* Amazon Kinesis Data Streams
* [And many more...](https://docs.aws.amazon.com/lambda/latest/dg/lambda-services.html)

We're going to try out Amazon SQS and Amazon CloudWatch Logs events.

### 2.1: Unit Test Suite

Create the following as `tests/app/test_event_handlers.rb`, to provide a basic test suite for the event handler function we will write.

`tests/app/test_event_handlers.rb`
```ruby
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
```

Note here that the structure of an SQS event message is different than an API Gateway event.

### 2.2: Creating an SQS Queue

For creating an SQS queue, all we need to do is add this to the `Resources` of our `template.yaml` file:

`template.yaml`
```yaml
DeletePostQueue:
  Type: AWS::SQS::Queue
```

We'll reference this resource when defining other methods.

### 2.3: Creating an SQS-Triggered Function

Now, we can define the `app/event_handlers.rb` file, which will contain our handlers for event-based methods. In it, we're going to define a method which:

1. Consumes the Amazon SQS event message format.
2. Validates that the message body is the exact message we expect, or raises an exception.
3. If the message body matches, iterate over every post in our database and delete it.

`app/event_handlers.rb`
```ruby
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
```

Then as before, we add our new method under the `Resources` section of our `template.yaml` file. Note here that the `Events` section has changed to support a different event source type (SQS rather than Api), but otherwise much of the format remains the same.

`template.yaml`
```yaml
DeleteAllEventHandler:
  Type: AWS::Serverless::Function
  Properties:
    CodeUri: app/
    Handler: event_handlers.EventHandlers.delete_all_posts
    Runtime: ruby2.5
    Policies:
      - DynamoDBCrudPolicy:
          TableName: !Ref PostsTable
    Environment:
      Variables:
        TABLE_NAME: !Ref PostsTable
    Events:
      QueueEvent:
        Type: SQS
        Properties:
          Queue: !GetAtt DeletePostQueue.Arn
```

### 2.4: Creating the "Delete All" Web API

Next, we want a way to trigger our event-based function. That's going to be a handler in our `web_api.rb` class, and a couple of additional private methods. What our handler will do is send off a "DELETE_ALL" message to Amazon SQS, and then return a `204` success code:

`app/web_api.rb`
```ruby
def delete_all(event:,context:)
  _sqs_client.send_message(
    queue_url: _sqs_queue_url,
    message_body: "DELETE_ALL"
  )
  return {
    statusCode: 204
  }
end

private
def _sqs_client
  require 'aws-sdk-sqs'
  @@sqs_client ||= Aws::SQS::Client.new
  @@sqs_client
end

def _sqs_queue_url
  ENV["SQS_QUEUE_URL"]
end
```

Now, we COULD perform the entire deletion process within this handler, and only return after completion. However, in the case of a large database with many entries, that could take a very long time, especially from the perspective of a calling user! You could imagine the use case of a post/comments relationship, where deleting a post deletes all comments. Perhaps your deletion function for a post deletes the post immediately (which could render all comments unviewable), but rather than wait to delete all comments individually, it cleans them up later as a delayed job. This is the pattern we are implementing here.

If you wanted to take this further, you could actually create a "Deletion Job" in a database, include that job ID in your SQS message, and provide APIs to track the status of a deletion job. This is not unlike the pattern seen in many AWS APIs, where very long running jobs will have a creation/initiation API, and "Describe" APIs to track the status of a job. Implementing this is a *BONUS EXERCISE* you could try after the workshop, if desired.

For now, we just need to add our new web API to `Resources` in the `template.yaml` file:

`template.yaml`
```yaml
DeleteAllHandler:
  Type: AWS::Serverless::Function
  Properties:
    CodeUri: app/
    Handler: web_api.WebApi.delete_all
    Runtime: ruby2.5
    Environment:
      Variables:
        SQS_QUEUE_URL: !Ref DeletePostQueue
    Policies:
      SQSSendMessagePolicy:
        QueueName: !GetAtt DeletePostQueue.QueueName
    Events:
      DeleteAllApi:
        Type: Api
        Properties:
          Path: /posts
          Method: DELETE
```

### 2.5: Deploying and Testing

We can build and deploy our set of handlers using the same pattern as before:

```
sam build
sam package --template-file .aws-sam/build/template.yaml --output-template-file packaged.yaml --s3-bucket $RAILSCONF_SOURCE_BUCKET
sam deploy --template-file packaged.yaml --stack-name railsconf2019 --capabilities CAPABILITY_IAM --region us-west-2
aws cloudformation describe-stacks --stack-name railsconf2019 --region us-west-2 --query 'Stacks[].Outputs'
```

Then, ensure we are noting our API endpoint from `describe-stacks` (it will not have changed if you've already stored it).

```
export RAILSCONF_API_ENDPOINT=https://12my34api56id.execute-api.us-west-2.amazonaws.com/Prod/posts
curl $RAILSCONF_API_ENDPOINT
```

Now, try creating a few posts, triggering a deletion job, and then checking the index call again.

```
curl -d '{"title":"One"}' $RAILSCONF_API_ENDPOINT
curl -d '{"title":"Two"}' $RAILSCONF_API_ENDPOINT
curl -d '{"title":"Three"}' $RAILSCONF_API_ENDPOINT
curl $RAILSCONF_API_ENDPOINT
curl -X DELETE $RAILSCONF_API_ENDPOINT
curl $RAILSCONF_API_ENDPOINT
```

The deletion generally goes from "placed in the queue" to "complete" in a fraction of a second, so the final command will likely show an empty result.

## Exercise 3: Creating CloudWatch Alarms

In this workshop, we're trying to not only build our first serverless applications, but get an idea of how to productionize our application. Building a CI/CD pipeline is part of that. The next part is visibility.

One mental transition to building event-based functions is the lack of immediately visible feedback. When you open a webpage or call a JSON API, if it fails it tends to be immediately obvious. What if our SQS event handler breaks? That's where alarms come in.

### 3.1: Creating an Error Alarm

The intention of this alarm is to raise an alarm when your function begins to throw errors. We're going to put this on the "Index" API, but the same pattern applies essentially to any AWS Lambda function we have.

Let's add the following to our `template.yaml` file:

`template.yaml`
```yaml
  WebApiIndexErrorAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: RailsconfApiIndexErrors
      Namespace: AWS/Lambda
      MetricName: Errors
      Dimensions:
        - Name: FunctionName
          Value: !Ref WebApiIndex
      ComparisonOperator: GreaterThanOrEqualToThreshold
      Statistic: Sum
      Threshold: 1
      EvaluationPeriods: 3
      Period: 60
      TreatMissingData: missing
```

To deploy, just zip and upload your source to your S3 bucket, and let your deployment pipeline do it's thing! We can do the same now after each change we make.

### 3.2: Creating a Latency Alarm

One important feature to keep in mind when designing latency alarms is that you can use extended statistics such as p-thresholds for latency, which are a more useful metric than averages for most use cases. We're going to build two latency alarms, p50 and p99 for our "Index" API function.

`template.yaml`
```yaml
  WebApiIndexLatencyP50Alarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: RailsconfApiIndexLatencyP50
      Namespace: AWS/Lambda
      MetricName: Duration
      Dimensions:
        - Name: FunctionName
          Value: !Ref WebApiIndex
      ComparisonOperator: GreaterThanOrEqualToThreshold
      ExtendedStatistic: p50
      Threshold: 250
      Unit: Milliseconds
      EvaluationPeriods: 3
      Period: 60
      TreatMissingData: missing
  WebApiIndexLatencyP99Alarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: RailsconfApiIndexLatencyP99
      Namespace: AWS/Lambda
      MetricName: Duration
      Dimensions:
        - Name: FunctionName
          Value: !Ref WebApiIndex
      ComparisonOperator: GreaterThanOrEqualToThreshold
      ExtendedStatistic: p99
      Threshold: 1000
      Unit: Milliseconds
      EvaluationPeriods: 3
      Period: 60
      TreatMissingData: missing
```

There are a couple pieces of configuration here that merit extra attention:

- We chose P50 and P99 thresholds of 250ms and 1000ms, respectively. These aren't universal numbers, they heavily depend on what your functions do, how much memory you assign to your function, and so on. A good rule of thumb is that you should observe your actual P50/P99 metrics over time, and set thresholds fairly close to observed numbers. Sudden increases in latency mean a sudden degredation in your user experience and possible an underlying issue, which is why we have these alarms in the first place. Overly conservative thresholds that never trigger aren't very useful.
- How you treat missing data is an important consideration. If you're building a low-traffic function that's only called occasionally, it would make sense to treat missing data points as "missing", which essentially means an evaluation period with no data is skipped. However, if your application is high traffic, you should use "breaching" for your missing data policy, which treats any evaluation period with missing data as if it were a failing metric. In this manner, your alarms will activate if your function appears to be down/not taking traffic.

### 3.3: Creating an SQS Dead Letter Queue and Alarm

One good way to get visibility into failures in event-based functions that use Amazon SQS is to create a dead letter queue, where messages that repeatedly fail to process are placed for manual investigation. Combined with an alarm, you can be alerted in the event that a message has failed its maximum retries.

`template.yaml`
```yaml
  DeletePostQueue:
    Type: AWS::SQS::Queue
    Properties:
      RedrivePolicy:
        deadLetterTargetArn: !GetAtt DeletePostDeadLetterQueue.Arn
        maxReceiveCount: 5
  DeletePostDeadLetterQueue:
    Type: AWS::SQS::Queue
  DeletePostDLQAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: RailsconfDeletePostDLQ
      Namespace: AWS/SQS
      MetricName: ApproximateNumberOfMessagesVisible
      Dimensions:
        - Name: QueueName
          Value: !GetAtt DeletePostDeadLetterQueue.QueueName
      ComparisonOperator: GreaterThanOrEqualToThreshold
      Statistic: Sum
      Threshold: 1
      EvaluationPeriods: 5
      Period: 60
      TreatMissingData: breaching
```

What does this do?

- Creates a second SQS queue to store "failed" messages (known as a "Dead Letter Queue").
- Configures our `DeletePostQueue` to drive any messages that are received more than 5 times to the "Dead Letter Queue".
- Creates an alarm on the DLQ which, if for 5 straight minutes the queue has at least one message waiting, triggers an alarm.

## Exercise 4: Creating a CI/CD Pipeline

We've got tests, and a process for building, packaging, and deploying our application. The next step is to create a pipeline that will test and deploy our changes anytime we push our source.

### 4.1: Creating the Pipeline Template

Included here is a CloudFormation template that creates a 3-step deployment process via AWS CodePipeline.

1. Source code is uploaded as a zip file (`railsconf-source.zip` or another name you can specify) and uploaded to a source bucket whose name you also specify.
    - A note: You can absolutely use AWS CodeCommit or GitHub as source actions. S3 is what we're going with in this workshop because it's simple to do with the tools we know we have installed.
2. Through AWS CodeBuild, your unit tests are run, and then your code is packaged for deployment.
3. Finally, AWS CloudFormation is used to deploy your changes to the same template we have already been using.

I recommend making a new folder (for e.g., `pipeline`), and create this file as `pipeline-template.yml` inside that folder. This is not the same template you use for your application, it's going to build and deploy your application template.

`pipeline/pipeline-template.yml`
```yaml
Parameters:
  AppStackName:
    Type: String
    Description: "The name of the CloudFormation stack you have deployed your application to."
    Default: railsconf2019
  PipelineName:
    Type: String
    Description: "Name of the CodePipeline to create."
  SourceBucketName:
    Type: String
    Description: "S3 bucket name to use for the source code."
  SourceZipKey:
    Type: String
    Description: "S3 key in the Source Bucket where source code is stored."
    Default: railsconf-source.zip
Resources:
  SourceCodeBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref SourceBucketName
      VersioningConfiguration:
        Status: Enabled
    DeletionPolicy: Retain
  LambdaPipelineArtifactsBucket:
    Type: AWS::S3::Bucket
    DeletionPolicy: Retain
  LambdaPipelineRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Action: sts:AssumeRole
            Effect: Allow
            Principal:
              Service: codepipeline.amazonaws.com
        Version: "2012-10-17"
  LambdaPipelineRoleDefaultPolicy:
    Type: AWS::IAM::Policy
    Properties:
      PolicyDocument:
        Statement:
          - Action:
              - s3:GetObject*
              - s3:GetBucket*
              - s3:List*
              - s3:DeleteObject*
              - s3:PutObject*
              - s3:Abort*
            Effect: Allow
            Resource:
              - Fn::GetAtt:
                  - LambdaPipelineArtifactsBucket
                  - Arn
              - Fn::Join:
                  - ""
                  - - Fn::GetAtt:
                        - LambdaPipelineArtifactsBucket
                        - Arn
                    - /*
          - Action:
              - s3:GetObject*
              - s3:GetBucket*
              - s3:List*
            Effect: Allow
            Resource:
              - Fn::GetAtt:
                  - SourceCodeBucket
                  - Arn
              - Fn::Join:
                  - ""
                  - - Fn::GetAtt:
                        - SourceCodeBucket
                        - Arn
                    - /*
          - Action:
              - codebuild:BatchGetBuilds
              - codebuild:StartBuild
              - codebuild:StopBuild
            Effect: Allow
            Resource:
              Fn::GetAtt:
                - BuildProject
                - Arn
          - Action: iam:PassRole
            Effect: Allow
            Resource:
              Fn::GetAtt:
                - CloudFormationDeploymentRole
                - Arn
          - Action:
              - cloudformation:CreateStack
              - cloudformation:DescribeStack*
              - cloudformation:GetStackPolicy
              - cloudformation:GetTemplate*
              - cloudformation:SetStackPolicy
              - cloudformation:UpdateStack
              - cloudformation:ValidateTemplate
            Effect: Allow
            Resource:
              Fn::Join:
                - ""
                - - "arn:"
                  - Ref: AWS::Partition
                  - ":cloudformation:"
                  - Ref: AWS::Region
                  - ":"
                  - Ref: AWS::AccountId
                  - ":stack/"
                  - Ref: AppStackName
                  - "/*"
        Version: "2012-10-17"
      PolicyName: LambdaPipelineRoleDefaultPolicy
      Roles:
        - Ref: LambdaPipelineRole
  LambdaPipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      RoleArn:
        Fn::GetAtt:
          - LambdaPipelineRole
          - Arn
      Stages:
        - Actions:
            - ActionTypeId:
                Category: Source
                Owner: AWS
                Provider: S3
                Version: "1"
              Configuration:
                S3Bucket:
                  Ref: SourceCodeBucket
                S3ObjectKey: !Ref SourceZipKey
                PollForSourceChanges: true
              InputArtifacts:
                []
              Name: S3Source
              OutputArtifacts:
                - Name: Artifact_InfrastructureStackS3Source
              RunOrder: 1
          Name: Source
        - Actions:
            - ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: "1"
              Configuration:
                ProjectName:
                  Ref: BuildProject
              InputArtifacts:
                - Name: Artifact_InfrastructureStackS3Source
              Name: BuildAction
              OutputArtifacts:
                - Name: Artifact_InfrastructureStackBuildAction
              RunOrder: 1
          Name: Build
        - Actions:
            - ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: CloudFormation
                Version: "1"
              Configuration:
                StackName: !Ref AppStackName
                ActionMode: CREATE_UPDATE
                TemplatePath: Artifact_InfrastructureStackBuildAction::packaged.yaml
                Capabilities: CAPABILITY_IAM,CAPABILITY_AUTO_EXPAND
                RoleArn:
                  Fn::GetAtt:
                    - CloudFormationDeploymentRole
                    - Arn
              InputArtifacts:
                - Name: Artifact_InfrastructureStackBuildAction
              Name: CloudFrontDeployment
              OutputArtifacts:
                []
              RunOrder: 1
          Name: Deploy
      ArtifactStore:
        Location:
          Ref: LambdaPipelineArtifactsBucket
        Type: S3
      Name: !Ref PipelineName
    DependsOn:
      - LambdaPipelineRole
      - LambdaPipelineRoleDefaultPolicy
  BuildProjectRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Action: sts:AssumeRole
            Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
        Version: "2012-10-17"
  BuildProjectRoleDefaultPolicy:
    Type: AWS::IAM::Policy
    Properties:
      PolicyDocument:
        Statement:
          - Action:
              - logs:CreateLogGroup
              - logs:CreateLogStream
              - logs:PutLogEvents
            Effect: Allow
            Resource:
              - Fn::Join:
                  - ""
                  - - "arn:"
                    - Ref: AWS::Partition
                    - ":logs:"
                    - Ref: AWS::Region
                    - ":"
                    - Ref: AWS::AccountId
                    - :log-group:/aws/codebuild/
                    - Ref: BuildProject
              - Fn::Join:
                  - ""
                  - - "arn:"
                    - Ref: AWS::Partition
                    - ":logs:"
                    - Ref: AWS::Region
                    - ":"
                    - Ref: AWS::AccountId
                    - :log-group:/aws/codebuild/
                    - Ref: BuildProject
                    - :*
          - Action:
              - s3:GetObject*
              - s3:GetBucket*
              - s3:List*
              - s3:DeleteObject*
              - s3:PutObject*
              - s3:Abort*
            Effect: Allow
            Resource:
              - Fn::GetAtt:
                  - LambdaPipelineArtifactsBucket
                  - Arn
              - Fn::Join:
                  - ""
                  - - Fn::GetAtt:
                        - LambdaPipelineArtifactsBucket
                        - Arn
                    - /*
          - Action:
              - s3:GetObject*
              - s3:GetBucket*
              - s3:List*
              - s3:DeleteObject*
              - s3:PutObject*
              - s3:Abort*
            Effect: Allow
            Resource:
              - Fn::GetAtt:
                  - SourceCodeBucket
                  - Arn
              - Fn::Join:
                  - ""
                  - - Fn::GetAtt:
                        - SourceCodeBucket
                        - Arn
                    - /*
        Version: "2012-10-17"
      PolicyName: BuildProjectRoleDefaultPolicy
      Roles:
        - Ref: BuildProjectRole
  BuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Artifacts:
        Type: CODEPIPELINE
      Environment:
        ComputeType: BUILD_GENERAL1_SMALL
        Image: aws/codebuild/ruby:2.5.3
        PrivilegedMode: false
        Type: LINUX_CONTAINER
        EnvironmentVariables:
          - Name: SOURCE_BUCKET_NAME
            Value: !Ref SourceBucketName
      ServiceRole:
        Fn::GetAtt:
          - BuildProjectRole
          - Arn
      Source:
        BuildSpec: buildspec.yml
        Type: CODEPIPELINE
  CloudFormationDeploymentRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Action: sts:AssumeRole
            Effect: Allow
            Principal:
              Service: cloudformation.amazonaws.com
        Version: "2012-10-17"
  CloudFormationDeploymentRoleDefaultPolicy:
    Type: AWS::IAM::Policy
    Properties:
      PolicyDocument:
        Statement:
          - Action: "*"
            Effect: Allow
            Resource: "*"
        Version: "2012-10-17"
      PolicyName: CloudFormationDeploymentRoleDefaultPolicy
      Roles:
        - Ref: CloudFormationDeploymentRole
```

It's a large file, but essentially it's just a CodePipeline, the S3 bucket for the source action, the CodeBuild job, the deployment action, and the relevant least privileged roles needed to perform said actions. We are going to focus on how to wire up our app to use this.

### 4.2: Creating a buildspec.yml File

In the root directory of our project (not in the `app/` folder), we're going to create a `buildspec.yml` file, which CodeBuild expects to know what operations to perform.

Essentially, we are going to run our unit tests, and then perform the build and package steps manually. All we need to pass on to the next stage after this is the `packaged.yaml` file generated by the package step.

`buildspec.yml`
```yaml
version: 0.2

phases:
  build:
    commands:
      - bundle install
      - ruby tests/app/test_web_api.rb
      - ruby tests/app/test_event_handlers.rb
      - cd app
      - bundle install --gemfile Gemfile
      - bundle install --gemfile Gemfile --deployment
      - cd ..
      - aws cloudformation package --template-file template.yaml --output-template-file packaged.yaml --s3-bucket $SOURCE_BUCKET_NAME

artifacts:
  type: zip
  files:
    - packaged.yaml
```

Remember to substitute "YOUR SOURCE BUCKET" for the bucket you created.

### 4.3: Deploying the Pipeline

Next up, we're going to create our pipeline. Select a unique name for your source bucket and keep a note of it as an environment variable or otherwise.

```
export RAILSCONF_SOURCE_BUCKET=my-railsconf-source-bucket
aws cloudformation deploy --template-file pipeline-template.yml --stack-name railsconf2019-pipeline --parameter-overrides SourceBucketName=$RAILSCONF_SOURCE_BUCKET PipelineName=railsconf2019 --capabilities CAPABILITY_IAM
```

### 4.4: Running a Pipeline Deployment

Once your pipeline is up and running, you simply need to zip and upload to your source bucket the files used in your build and deploy process.

```
zip -r railsconf-source.zip Gemfile* app* buildspec.yml template.yaml tests*
aws s3 cp railsconf-source.zip s3://$RAILSCONF_SOURCE_BUCKET
```

You can view your deploying in the [AWS Console page for AWS CodePipeline](https://us-west-2.console.aws.amazon.com/codesuite/codepipeline/pipelines) - make sure you select the region you created your pipeline in.
