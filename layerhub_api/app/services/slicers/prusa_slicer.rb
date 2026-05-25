# frozen_string_literal: true

require "open3"

module Slicers
  class PrusaSlicer < BaseSlicer
    EXECUTABLE = ENV.fetch("PRUSASLICER_PATH", "prusa-slicer")

    SETTING_MAP = {
      "layer_height"     => "--layer-height",
      "first_layer_height" => "--first-layer-height",
      "infill"           => "--fill-density",
      "infill_pattern"   => "--fill-pattern",
      "wall_count"       => "--perimeters",
      "top_layers"       => "--top-solid-layers",
      "bottom_layers"    => "--bottom-solid-layers",
      "support"          => "--support-material",
      "support_density"  => "--support-material-spacing",
      "brim_width"       => "--brim-width",
      "skirt_loops"      => "--skirts",
      "print_speed"      => "--perimeter-speed",
      "nozzle_diameter"  => "--nozzle-diameter"
    }.freeze

    def slice(input_path, output_path, profile: nil, settings: {})
      cmd = build_command(input_path, output_path, profile, settings)
      run_command(cmd)
    end

    private

    def build_command(input_path, output_path, profile, settings)
      parts = [
        EXECUTABLE,
        "--export-gcode",
        "--output", shell_escape(output_path)
      ]
      parts.push("--load", shell_escape(profile)) if profile

      (settings || {}).each do |key, value|
        flag = SETTING_MAP[key.to_s]
        next unless flag

        if key.to_s == "support"
          # Boolean toggle — only add the flag if truthy
          parts.push(flag) if value == true || value == "true" || value == "1"
        elsif key.to_s == "infill"
          parts.push(flag, "#{value}%")
        else
          parts.push(flag, value.to_s)
        end
      end

      parts.push(shell_escape(input_path))
      parts.join(" ")
    end

    def shell_escape(path)
      Shellwords.escape(path)
    end
  end
end
