# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'json'
require 'sorbet-runtime'
require_relative 'fake_https'

# The responses of an OCI registry, for the specs of the scripts that read one.
module TagPages
  extend T::Sig

  # The Accept header of the manifest requests of Outdated::Registry.
  MANIFEST_TYPES = 'application/vnd.oci.image.index.v1+json, ' \
    'application/vnd.docker.distribution.manifest.list.v2+json, ' \
    'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
  public_constant :MANIFEST_TYPES

  # A page of the tag list of a repository.
  # @param tags [Array<String>]
  # @param next_page [String, nil] the path of the next page, if any
  # @return [Net::HTTPResponse]
  sig { params(tags: T::Array[String], next_page: T.nilable(String)).returns(Net::HTTPResponse) }
  def self.page(tags, next_page: nil)
    headers = next_page ? [['Link', "<#{next_page}>; rel=\"next\""]] : []
    FakeHttps.response('200 OK', body: JSON.generate({ name: 'image', tags: }), headers:)
  end
end
