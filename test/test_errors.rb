# frozen_string_literal: true

require "helper"

describe ::HermesAgent::Client::APIError do
  api_error = ::HermesAgent::Client::APIError
  errors = ::HermesAgent::Client

  describe "hierarchy" do
    it "roots every error at Error < StandardError" do
      assert_operator(errors::Error, :<, ::StandardError)
    end

    it "places transport-level failures directly under Error, not APIError" do
      assert_operator(errors::ConnectionError, :<, errors::Error)
      assert_operator(errors::TimeoutError, :<, errors::Error)
      refute_operator(errors::ConnectionError, :<, api_error)
      refute_operator(errors::TimeoutError, :<, api_error)
    end

    it "places status-specific errors under APIError" do
      [errors::BadRequestError, errors::AuthenticationError, errors::PermissionError,
       errors::NotFoundError, errors::RateLimitError, errors::ServerError].each do |klass|
        assert_operator(klass, :<, api_error)
      end
    end
  end

  describe ".from_response" do
    it "maps status codes to the matching subclass" do
      mapping = {
        400 => errors::BadRequestError,
        422 => errors::BadRequestError,
        401 => errors::AuthenticationError,
        403 => errors::PermissionError,
        404 => errors::NotFoundError,
        429 => errors::RateLimitError,
        500 => errors::ServerError,
        503 => errors::ServerError,
        418 => api_error,
      }
      mapping.each do |status, klass|
        error = api_error.from_response(status: status, body: "")
        assert_instance_of(klass, error)
      end
    end

    it "parses an OpenAI-style structured error body" do
      body = '{"error":{"message":"Invalid API key","type":"invalid_request_error",' \
             '"code":"invalid_api_key"}}'
      error = api_error.from_response(status: 401, body: body)
      assert_instance_of(errors::AuthenticationError, error)
      assert_equal("Invalid API key", error.message)
      assert_equal("invalid_api_key", error.error["code"])
      assert_equal("invalid_request_error", error.error["type"])
    end

    it "tolerates a non-JSON router-level error body" do
      error = api_error.from_response(status: 404, body: "404: Not Found")
      assert_instance_of(errors::NotFoundError, error)
      assert_nil(error.error)
      assert_equal("404: Not Found", error.body)
      refute_empty(error.message)
    end

    it "exposes nil #error for JSON that lacks an error object" do
      error = api_error.from_response(status: 400, body: '{"detail":"nope"}')
      assert_nil(error.error)
    end

    it "retains status, body, and headers" do
      error = api_error.from_response(status: 429, body: "slow down",
                                      headers: {"retry-after" => "5"})
      assert_equal(429, error.status)
      assert_equal("slow down", error.body)
      assert_equal("5", error.headers["retry-after"])
    end
  end
end
