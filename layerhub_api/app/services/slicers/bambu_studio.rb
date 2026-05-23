# frozen_string_literal: true

require "open3"

module Slicers
  class BambuStudio < BaseSlicer
    EXECUTABLE = ENV.fetch("BAMBU_STUDIO_PATH", "bambu-studio")

    def slice(input_path, output_path, profile: nil)
      cmd = build_command(input_path, output_path, profile)
      run_command(cmd)
    end

    private

    def build_command(input_path, output_path, profile)
      parts = [
        EXECUTABLE,
        "--export-gcode",
        "--output", shell_escape(output_path),
        shell_escape(input_path)
      ]
      parts.push("--load-settings", shell_escape(profile)) if profile
      parts.join(" ")
    end

    def shell_escape(path)
      Shellwords.escape(path)
    end
  end
end
