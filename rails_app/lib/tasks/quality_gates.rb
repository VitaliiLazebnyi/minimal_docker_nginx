# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require 'tmpdir'

# The commands and helpers of the quality-gate tasks of the Rakefile.
module QualityGates
  extend T::Sig

  # The repository root: the shell gates and the outdated check cover the whole repository, not only the app.
  REPOSITORY_ROOT = T.let(File.expand_path('../../..', __dir__), String)
  # Ruby code outside the application: the repository scripts (the outdated and Scorecard checks), linted,
  # typed, documented and smell-checked with the application's configuration.
  SCRIPTS = T.let(File.join(REPOSITORY_ROOT, 'script'), String)
  # The Ruby code every analysis covers (the Rakefile runs the helpers of this module).
  SOURCES = T.let(['Rakefile', 'app', 'lib', SCRIPTS].freeze, T::Array[String])
  # Output of `yard stats` when every object (.yardopts: private and protected ones included) is documented.
  FULLY_DOCUMENTED = '100.00% documented'
  public_constant :REPOSITORY_ROOT, :SCRIPTS, :SOURCES, :FULLY_DOCUMENTED

  # Ruby programs of the bundle that are not run through their executables: `[*RUBY, program, '--', *arguments]`.
  module Programs
    # Runs a Ruby program with the default encodings UTF-8 from the start (`-E`), so a tool that sets them itself
    # (YARD, Brakeman) does not warn about changing them.
    RUBY = %w[bundle exec ruby -Eutf-8:utf-8 -e].freeze
    # YARD (`yard <command> ...`) with the yard-sorbet plugin. The plugin is required once YARD is loaded: named in
    # .yardopts (`--plugin`), YARD would load it while yard.rb itself is still loading, and the plugin's own
    # `require 'yard'` would be a circular require (a Ruby warning).
    YARD = 'require "yard"; require "yard-sorbet"; YARD::CLI::CommandParser.run(*ARGV)'
    # Brakeman, as its executable runs it.
    BRAKEMAN = 'require "brakeman"; require "brakeman/commandline"; Brakeman::Commandline.start'
    public_constant :RUBY, :YARD, :BRAKEMAN
  end

  # The method complexity gate (`rake flog`).
  module Complexity
    extend T::Sig

    # Flog score above which a single method counts as too complex and must be split up (Flog's own guidance:
    # 0-10 is good, 11-20 needs a look, above 20 needs refactoring).
    THRESHOLD = 20
    # A method of the report of `flog --all --methods-only`: its score, its name and its location.
    METHOD = /^\s*\d+\.\d: \S+\s+\S+:\d/
    public_constant :THRESHOLD, :METHOD

    # The score and name of every method of +report+ that Flog rates above THRESHOLD.
    # @param report [String] the output of `flog --all --methods-only`
    # @return [Array<String>] "score: method" of each method that is too complex
    sig { params(report: String).returns(T::Array[String]) }
    def self.complex_methods(report)
      complex = report.each_line.grep(METHOD).select { |line| score(line) > THRESHOLD }
      complex.map { |line| line.split.first(2).join(' ') }
    end

    # The score of a method line of the report.
    # @param line [String] a line that matches METHOD
    # @return [Float]
    sig { params(line: String).returns(Float) }
    def self.score(line)
      Float(line.split.fetch(0).delete_suffix(':'))
    end
  end

  # Runs +command+ in +directory+.
  # @param command [Array<String>]
  # @param directory [String] the working directory of the command
  # @return [Array(String, Process::Status)] its output (standard output and error) and its exit status
  sig { params(command: T::Array[String], directory: String).returns([String, T.nilable(Process::Status)]) }
  def self.run(command, directory: Dir.pwd)
    pipe = T.let(IO.popen(command, chdir: directory, err: %i[child out]), IO)
    output = pipe.read
    pipe.close
    [output, Process.last_status]
  end

  # Writes +lines+ to a temporary file, and yields its path; the file is deleted afterwards.
  # @param lines [Array<String>]
  # @yieldparam path [String]
  sig { params(lines: T::Array[String], block: T.proc.params(path: String).void).void }
  def self.with_file(lines, &block)
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'lines')
      File.write(path, lines.join("\n"))
      yield(path)
    end
  end
end
