# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require_relative 'document'
require_relative 'registry'
require_relative 'report'

module Outdated
  # Every Docker image pinned as name:tag@sha256:digest must use the newest tag of its shape, and the digest
  # the tag currently points to.
  class Images
    extend T::Sig

    REFERENCE = %r{(?<name>[a-z0-9][a-z0-9./_-]*):(?<tag>\w[\w.-]*)@sha256:(?<digest>\h{64})}
    private_constant :REFERENCE

    # An image reference found in a file.
    class Pin < T::Struct
      extend T::Sig

      const :location, String
      const :name, String
      const :tag, String
      const :digest, String

      # Reports the tag unless it is the newest of its shape, and the digest unless the tag still points to it.
      # @param report [Report]
      sig { params(report: Report).void }
      def check(report)
        registry = Registry.for(name)
        pinned = tag
        label = "#{name}:#{pinned} (#{location})"
        report.compare("image tag of #{label}", pinned, Images.newest_tag(registry.tags, pinned))
        report.compare("image digest of #{label}", digest, registry.digest(pinned))
      end
    end

    # The image references of a file.
    # @param path [String]
    # @return [Array<Pin>]
    sig { params(path: String).returns(T::Array[Pin]) }
    def self.pins_in(path)
      location = Outdated.relative(path)
      File.read(path).scan(REFERENCE).map do |name, tag, digest|
        Pin.new(location:, name: name.to_s, tag: tag.to_s, digest: "sha256:#{digest}")
      end
    end

    # The highest tag with the same shape as +tag+: the same text, with any numbers in place of its numbers
    # (so "4.0.9-alpine3.24" is compared with "4.0.10-alpine3.24" or "4.1.0-alpine3.25", never with "4-slim").
    # @param tags [Array<String>] every tag of the repository
    # @param tag [String] the pinned tag
    # @return [String]
    sig { params(tags: T::Array[String], tag: String).returns(String) }
    def self.newest_tag(tags, tag)
      parts = tag.split(/\d+/, -1).map { |part| Regexp.escape(part) }
      shape = Regexp.new("\\A#{parts.join('(\d+)')}\\z")
      tags.grep(shape).max_by { |candidate| numbers(candidate) } || tag
    end

    # The numbers in +tag+, in order ("4.0.9-alpine3.24" => [4, 0, 9, 3, 24]).
    # @param tag [String]
    # @return [Array<Integer>]
    sig { params(tag: String).returns(T::Array[Integer]) }
    def self.numbers(tag)
      tag.scan(/\d+/).map { |number| Integer(number.to_s, 10) }
    end

    # The images of tools/images.json, each pinned as name, tag and digest.
    # @param path [String]
    # @return [Array<Pin>]
    sig { params(path: String).returns(T::Array[Pin]) }
    def self.pins_in_json(path)
      document = Document.parse(File.read(path))
      location = Outdated.relative(path)
      Document.entries(document).map { |key| json_pin(document, key, "#{location} #{key}") }
    end

    # The image +key+ of a parsed tools/images.json.
    # @param document [Object]
    # @param key [String]
    # @param location [String] where the image is pinned, for messages
    # @return [Pin]
    sig { params(document: Object, key: String, location: String).returns(Pin) }
    def self.json_pin(document, key, location)
      Pin.new(
        location:,
        name: Document.string(document, [key, 'name']),
        tag: Document.string(document, [key, 'tag']),
        digest: Document.string(document, [key, 'digest'])
      )
    end

    # Every pinned image: those of the Dockerfile and the workflows, and those of tools/images.json.
    # @return [Array<Pin>]
    sig { returns(T::Array[Pin]) }
    def self.pins
      PINNING_FILES.flat_map { |path| pins_in(path) } + pins_in_json(File.join(ROOT, 'tools', 'images.json'))
    end

    # @param report [Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Runs the checks.
    sig { void }
    def check
      Images.pins.each { |pin| pin.check(@report) }
    end
  end
end
