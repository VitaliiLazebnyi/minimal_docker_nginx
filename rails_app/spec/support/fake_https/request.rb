# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'

# The HTTPS server of the specs (spec/support/fake_https.rb).
class FakeHttps
  # A request received: the method (verb), the URL and the headers.
  class Request < T::Struct
    extend T::Sig

    const :verb, String
    const :url, String
    const :headers, T::Hash[String, String]

    # The value of the header +name+ (in lower case), or nil when the request has no such header.
    # @param name [String]
    # @return [String, nil]
    sig { params(name: String).returns(T.nilable(String)) }
    def header(name)
      headers[name]
    end
  end
end
