# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/document'

RSpec.describe(Outdated::Document) do
  sig { returns(Object) }
  let(:document) { described_class.parse('{"$comment": ["x"], "a": {"b": "text", "n": 1, "list": [1, "two"]}}') }

  describe '.parse' do
    it 'parses a JSON document' do
      expect(described_class.at(described_class.parse('{"a": [1, null]}'), ['a'])).to(eq([1, nil]))
    end
  end

  describe '.load' do
    it 'loads a YAML file' do
      Tempfile.create(['document', '.yml']) do |file|
        File.write(file.path, "a:\n  - b\n")
        expect(described_class.load(file.path)).to(eq(described_class.parse('{"a": ["b"]}')))
      end
    end

    it 'refuses the YAML tags of arbitrary objects' do
      Tempfile.create(['document', '.yml']) do |file|
        File.write(file.path, "--- !ruby/object:Object {}\n")
        expect { described_class.load(file.path) }
          .to(raise_error(Psych::DisallowedClass))
      end
    end
  end

  describe '.entries' do
    it 'returns the keys of a mapping, without the $comment of a JSON document' do
      expect(described_class.entries(document)).to(eq(['a']))
    end
  end

  describe '.key?' do
    it 'is true when the node is a mapping with the key' do
      expect(described_class.key?(document, 'a')).to(be(true))
    end

    it 'is false when the node is a mapping without the key' do
      expect(described_class.key?(document, 'b')).to(be(false))
    end

    it 'is false when the node is not a mapping' do
      expect(described_class.key?(['a'], 'a')).to(be(false))
    end
  end

  describe '.at' do
    it 'returns the value at the path' do
      expect(described_class.at(document, %w[a n])).to(eq(1))
    end

    it 'returns the document itself for an empty path' do
      expect(described_class.at(document, [])).to(be(document))
    end

    it 'raises a KeyError when a key is missing' do
      expect { described_class.at(document, %w[a missing]) }
        .to(raise_error(KeyError))
    end

    it 'raises when a value on the path is not a mapping, naming the key and the value' do
      expect { described_class.at(document, %w[a b c]) }
        .to(raise_error(ArgumentError, 'no "c" in "text"'))
    end

    it 'shortens the value it names to 80 characters' do
      expect { described_class.at(['x' * 100], ['k']) }
        .to(raise_error(ArgumentError, "no \"k\" in #{['x' * 100].inspect[0, 80]}"))
    end
  end

  describe '.string' do
    it 'returns the string at the path' do
      expect(described_class.string(document, %w[a b])).to(eq('text'))
    end

    it 'raises when the value is not a string, naming its path' do
      expect { described_class.string(document, %w[a n]) }
        .to(raise_error(ArgumentError, 'a.n is not a string: 1'))
    end

    it 'raises when the value is not a string, naming the value' do
      expect { described_class.string(described_class.parse('{"n": null}'), ['n']) }
        .to(raise_error(ArgumentError, 'n is not a string: nil'))
    end
  end

  describe '.keys' do
    it 'returns the keys of the mapping at the path, as strings' do
      expect(described_class.keys(Psych.safe_load("'3.3': x\n4: y\n"), [])).to(eq(%w[3.3 4]))
    end

    it 'raises when the value is not a mapping, naming the path and the value' do
      expect { described_class.keys(document, %w[a b]) }
        .to(raise_error(ArgumentError, 'a.b is not a mapping: "text"'))
    end

    it 'names a null value as nil' do
      expect { described_class.keys(described_class.parse('{"a": null}'), ['a']) }
        .to(raise_error(ArgumentError, 'a is not a mapping: nil'))
    end
  end

  describe '.list' do
    it 'returns the items of the list under the key' do
      expect(described_class.list(described_class.at(document, ['a']), 'list')).to(eq([1, 'two']))
    end

    it 'returns no item when the key is absent' do
      expect(described_class.list(document, 'list')).to(eq([]))
    end

    it 'returns no item when the node is not a mapping' do
      expect(described_class.list(['list'], 'list')).to(eq([]))
    end

    it 'returns no item when the list is null' do
      expect(described_class.list(described_class.parse('{"list": null}'), 'list')).to(eq([]))
    end

    it 'raises when the value is not a list, naming the key and the value' do
      expect { described_class.list(described_class.parse('{"list": "x"}'), 'list') }
        .to(raise_error(ArgumentError, 'list is not a list: "x"'))
    end
  end

  describe '.strings' do
    it 'returns the items of the list under the key, as strings' do
      expect(described_class.strings(described_class.at(document, ['a']), 'list')).to(eq(%w[1 two]))
    end
  end
end
