# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Outdated
  # Typed access to parsed JSON and YAML documents: every value is checked when it is read, so a document of
  # an unexpected shape fails loudly instead of flowing on untyped.
  module Document
    extend T::Sig

    # Whether the mapping at +keys+ (all but the last) has the last key.
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [Boolean]
    sig { params(node: Object, keys: T::Array[String]).returns(T::Boolean) }
    def self.key?(node, keys)
      parent = at(node, keys[0...-1] || [])
      parent.is_a?(Hash) && parent.key?(keys.last)
    end

    # The value at +keys+.
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [Object]
    sig { params(node: Object, keys: T::Array[String]).returns(Object) }
    def self.at(node, keys)
      keys.reduce(node) do |current, key|
        raise ArgumentError, "no #{key.inspect} in #{current.inspect[0, 80]}" unless current.is_a?(Hash)

        current.fetch(key)
      end
    end

    # The string at +keys+.
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [String]
    sig { params(node: Object, keys: T::Array[String]).returns(String) }
    def self.string(node, keys)
      value = at(node, keys)
      raise ArgumentError, "#{keys.join('.')} is not a string: #{value.inspect}" unless value.is_a?(String)

      value
    end

    # The keys of the mapping at +keys+.
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [Array<String>]
    sig { params(node: Object, keys: T::Array[String]).returns(T::Array[String]) }
    def self.keys(node, keys)
      value = at(node, keys)
      raise ArgumentError, "#{keys.join('.')} is not a mapping: #{value.inspect}" unless value.is_a?(Hash)

      value.keys.map(&:to_s)
    end

    # The strings of the list at +keys+ (an absent or null list is empty).
    # @param node [Object] a parsed document
    # @param keys [Array<String>]
    # @return [Array<String>]
    sig { params(node: Object, keys: T::Array[String]).returns(T::Array[String]) }
    def self.strings(node, keys)
      case (value = key?(node, keys) ? at(node, keys) : [])
      when Array then value.map(&:to_s)
      when NilClass then []
      else raise ArgumentError, "#{keys.join('.')} is not a list: #{value.inspect}"
      end
    end
  end
end
