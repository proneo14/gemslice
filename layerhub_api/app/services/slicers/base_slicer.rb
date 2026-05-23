# frozen_string_literal: true

module Slicers
  class BaseSlicer
    SliceError = Class.new(StandardError)

    # @param input_path  [String] absolute path to the source STL file
    # @param output_path [String] absolute path where the G-code should be written
    # @param profile     [String] optional slicer profile name
    # @return [Boolean] true on success
    # @raise  [SliceError] on failure
    def slice(input_path, output_path, profile: nil)
      raise NotImplementedError, "#{self.class}#slice must be implemented"
    end

    private

    def run_command(cmd)
      stdout_err, status = Open3.capture2e(cmd)
      return true if status.success?

      raise SliceError, "Slicer command failed (exit #{status.exitstatus}): #{stdout_err.truncate(500)}"
    end
  end
end
