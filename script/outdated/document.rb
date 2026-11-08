# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'json'
require 'sorbet-runtime'
require 'yaml'

module Outdated
  # Typed access to parsed JSON and YAML documents: every value is checked when it is read, so a document of
  # an unexpected shape fails loudly instead of flowing on untyped.
  module Document
    extend T::Sig

    # Parses a JSON document (read it with the other methods of this module).
    # @param json [String]
    # @return [Object]
    sig { params(json: String).returns(Object) }
    def self.parse(json)
      T.let(JSON.parse(json), Object)
    end

    # Loads a YAML file (read it with the other methods of this module).
    # @param path [String]
    # @return [Object]
    sig { params(path: String).returns(Object) }
    def self.load(path)
      T.let(YAML.safe_load_file(path), Object)
    end

    # The keys of the mapping +node+, without the `$comment` of a JSON document (JSON has no comments).
    # @param node [Object] a parsed document
    # @return [Array<String>]
    sig { params(node: Object).returns(T::Array[String]) }
    def self.entries(node)
      keys(node, []).reject { |key| key.start_with?('$') }
    end

    # Whether +node+ is a mapping that has +key+.
    # @param node [Object] a parsed document
    # @param key [String]
    # @return [Boolean]
    sig { params(node: Object, key: String).returns(T::Boolean) }
    def self.key?(node, key)
      case node
      when Hash then node.key?(key)
      else false
      end
    end

    # The value at +keys+.
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [Object]
    sig { params(node: Object, keys: T::Array[String]).returns(Object) }
    def self.at(node, keys)
      keys.reduce(node) do |current, key|
        case current
        when Hash then T.let(current.fetch(key), Object)
        else raise(ArgumentError, "no #{key.inspect} in #{current.inspect[0, 80]}")
        end
      end
    end

    # The string at +keys+.
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [String]
    sig { params(node: Object, keys: T::Array[String]).returns(String) }
    def self.string(node, keys)
      case (value = at(node, keys))
      when String then value
      else raise(ArgumentError, "#{keys.join('.')} is not a string: #{value.inspect}")
      end
    end

    # The keys of the mapping at +keys+.
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [Array<String>]
    sig { params(node: Object, keys: T::Array[String]).returns(T::Array[String]) }
    def self.keys(node, keys)
      case (value = at(node, keys))
      when Hash then value.keys.map { |key| T.let(key, Object).to_s }
      else raise(ArgumentError, "#{keys.join('.')} is not a mapping: #{value.inspect}")
      end
    end

    # The items of the list under +key+ of the mapping +node+ (an absent or null list is empty).
    # @param node [Object] a parsed document
    # @param key [String]
    # @return [Array<Object>]
    sig { params(node: Object, key: String).returns(T::Array[Object]) }
    def self.list(node, key)
      return [] unless key?(node, key)

      case (value = at(node, [key]) || [])
      when Array then value
      else raise(ArgumentError, "#{key} is not a list: #{value.inspect}")
      end
    end

    # The items of the list under +key+ of the mapping +node+, as strings (an absent or null list is empty).
    # @param node [Object] a parsed document
    # @param key [String]
    # @return [Array<String>]
    sig { params(node: Object, key: String).returns(T::Array[String]) }
    def self.strings(node, key)
      list(node, key).map(&:to_s)
    end
  end
end
