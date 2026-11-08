# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"
require "time"

module Jtr
  ROOT = File.expand_path("..", __dir__)

  class Error < StandardError; end
end

require_relative "jtr/task_set"
require_relative "jtr/diagnostics"
require_relative "jtr/rubric"
require_relative "jtr/judge_schema"
require_relative "jtr/store"
require_relative "jtr/judge"
require_relative "jtr/stub_judge"
require_relative "jtr/bradley_terry"
require_relative "jtr/report"
require_relative "jtr/generators/command"
require_relative "jtr/generators/claude"
require_relative "jtr/cli"
