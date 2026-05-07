# frozen_string_literal: true

require "sequel"

module Sowing
  module Infrastructure
    module DB
      class << self
        attr_reader :connection

        def connect!
          return @connection if @connection

          path = Paths.db_path
          @connection = Sequel.sqlite(path)
          @connection.run("PRAGMA journal_mode = WAL;")
          @connection.run("PRAGMA foreign_keys = ON;")
          @connection.run("PRAGMA synchronous = NORMAL;")
          @connection
        end

        def disconnect!
          @connection&.disconnect
          @connection = nil
        end
      end
    end
  end
end
